#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "game/game.hpp"

#include "workshop.hpp"
#include "download.hpp"
#include "console/console.hpp"
#include "directx.hpp"
#include "scheduler.hpp"

#include "game/ui_scripting/execution.hpp"

#include "utils/hash.hpp"

#include <utils/concurrency.hpp>
#include <utils/hook.hpp>
#include <utils/http.hpp>
#include <utils/io.hpp>
#include <utils/json.hpp>
#include <utils/string.hpp>

#pragma warning(push)
#pragma warning(disable: 4459)
#include <DirectXTex.h>
#pragma warning(pop)

namespace workshop
{
	namespace
	{
		constexpr auto max_preview_size = 16ull * 1024ull * 1024ull;
		constexpr auto max_preview_dimension = 1024ull;

		struct file_t
		{
			std::string name;
			std::string hash;
			std::uint64_t size{};
			std::vector<std::string> urls;
		};

		struct entry_t
		{
			item_t item;
			std::string image;
			std::vector<file_t> files;
		};

		struct preview_t
		{
			std::string name;
			game::GfxImage image{};
			game::Material material{};
			std::vector<game::MaterialTextureDef> textures{};
		};

		const game::dvar_t* workshop_url = nullptr;
		std::atomic_bool refreshing = false;
		utils::concurrency::container<std::vector<entry_t>> entries;
		utils::concurrency::container<std::unordered_map<std::string, std::unique_ptr<preview_t>>> previews;

		std::vector<std::string> usermap_extensions =
		{
			".ff",
			"_load.ff",
			"_art.ff",
			".arena",
			".pak",
			".sabl",
			".sabs",
		};

		std::vector<std::string> mod_files =
		{
			"mod.ff",
			"mod.sabl",
			"mod.sabs",
		};

		bool is_valid_name(const std::string& name, const size_t max_length)
		{
			if (name.empty() || name.size() > max_length)
			{
				return false;
			}

			return std::ranges::all_of(name, [](const char c)
			{
				return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_';
			});
		}

		bool is_valid_url(const std::string& url)
		{
			if (url.starts_with("https://"))
			{
				return true;
			}

			for (const std::string host : {"http://localhost", "http://127.0.0.1"})
			{
				if (url.size() > host.size() && url.starts_with(host) && (url[host.size()] == ':' || url[host.size()] == '/'))
				{
					return true;
				}
			}

			return false;
		}

		bool is_valid_file(const item_t& item, const std::string& name)
		{
			if (item.type == "mod")
			{
				return std::ranges::find(mod_files, name) != mod_files.end();
			}

			for (const auto& extension : usermap_extensions)
			{
				if (name == item.id + extension)
				{
					return true;
				}
			}

			const auto localized = "_" + item.id + ".ff";
			return name.ends_with(localized) && is_valid_name(name.substr(0, name.size() - localized.size()), 16);
		}

		std::string get_main_file(const item_t& item)
		{
			return item.type == "mod" ? "mod.ff" : item.id + ".ff";
		}

		std::string get_folder(const item_t& item)
		{
			return std::format("{}/{}", item.type == "mod" ? "mods" : "usermaps", item.id);
		}

		std::string get_path(const item_t& item, const file_t& file)
		{
			return std::format("{}/{}", get_folder(item), file.name);
		}

		std::optional<entry_t> parse_entry(const nlohmann::json& value)
		{
			entry_t entry{};
			entry.item.id = value.value("id", "");
			entry.item.type = value.value("type", "");
			entry.item.name = value.value("name", entry.item.id);
			entry.item.author = value.value("author", "");
			entry.item.description = value.value("description", "");
			entry.item.version = value.value("version", "");
			entry.image = value.value("image", "");

			if (!is_valid_name(entry.item.id, 64) || (entry.item.type != "map" && entry.item.type != "mod"))
			{
				return {};
			}

			if (!entry.image.empty() && !is_valid_url(entry.image))
			{
				return {};
			}

			if (!value.contains("files") || (value["files"].is_array() && value["files"].empty()))
			{
				if (entry.image.empty())
				{
					return {};
				}

				return {entry};
			}

			if (!value["files"].is_array())
			{
				return {};
			}

			auto has_main_file = false;
			for (const auto& file_value : value["files"])
			{
				if (!file_value.is_object())
				{
					return {};
				}

				file_t file{};
				file.name = file_value.value("name", "");
				file.hash = file_value.value("hash", "");
				file.size = file_value.value("size", 0ull);
				file.urls = file_value.value("urls", std::vector<std::string>{});

				if (!is_valid_file(entry.item, file.name) || file.hash.empty() || file.urls.empty())
				{
					return {};
				}

				for (const auto& url : file.urls)
				{
					if (!is_valid_url(url))
					{
						return {};
					}
				}

				if (std::ranges::find_if(entry.files, [&](const file_t& other) { return other.name == file.name; }) != entry.files.end())
				{
					return {};
				}

				has_main_file = has_main_file || file.name == get_main_file(entry.item);
				entry.item.size += file.size;
				entry.files.emplace_back(file);
			}

			if (!has_main_file)
			{
				return {};
			}

			return {entry};
		}

		std::vector<entry_t> parse_catalog(const std::string& data)
		{
			const auto obj = nlohmann::json::parse(data);
			if (!obj.contains("items") || !obj["items"].is_array())
			{
				throw std::runtime_error("Workshop catalog has no items");
			}

			std::vector<entry_t> result{};
			for (const auto& value : obj["items"])
			{
				if (!value.is_object())
				{
					continue;
				}

				std::optional<entry_t> entry{};
				try
				{
					entry = parse_entry(value);
				}
				catch (const nlohmann::json::exception&)
				{
				}

				if (!entry.has_value())
				{
					const auto id = value.contains("id") && value["id"].is_string() ? value["id"].get<std::string>() : "";
					console::warn("Skipping invalid workshop item '%s'\n", id.data());
					continue;
				}

				if (std::ranges::find_if(result, [&](const entry_t& other) { return other.item.id == entry->item.id; }) != result.end())
				{
					console::warn("Skipping duplicate workshop item '%s'\n", entry->item.id.data());
					continue;
				}

				result.emplace_back(entry.value());
			}

			return result;
		}

		std::vector<download::file_t> get_outdated_files(const entry_t& entry)
		{
			std::vector<download::file_t> files{};
			for (const auto& file : entry.files)
			{
				const auto path = get_path(entry.item, file);
				if (utils::hash::get_file_hash(path) != file.hash)
				{
					files.emplace_back(path, file.hash, file.urls);
				}
			}

			return files;
		}

		void update_state(entry_t& entry)
		{
			if (entry.files.empty())
			{
				entry.item.state = "soon";
				return;
			}

			if (!utils::io::file_exists(std::format("{}/{}", get_folder(entry.item), get_main_file(entry.item))))
			{
				entry.item.state = "none";
				return;
			}

			entry.item.state = get_outdated_files(entry).empty() ? "installed" : "update";
		}

		std::optional<entry_t> find_entry(const std::string& id)
		{
			return entries.access<std::optional<entry_t>>([&](const std::vector<entry_t>& entries_) -> std::optional<entry_t>
			{
				for (const auto& entry : entries_)
				{
					if (entry.item.id == id)
					{
						return {entry};
					}
				}

				return {};
			});
		}

		std::string get_preview_name(const std::string& id)
		{
			return "workshop_" + id;
		}

		bool has_preview(const std::string& name)
		{
			return previews.access<bool>([&](const std::unordered_map<std::string, std::unique_ptr<preview_t>>& previews_)
			{
				return previews_.contains(name);
			});
		}

		game::Material* register_material_stub(const char* name)
		{
			const auto material = previews.access<game::Material*>([&](const std::unordered_map<std::string, std::unique_ptr<preview_t>>& previews_) -> game::Material*
			{
				const auto preview = previews_.find(name);
				return preview != previews_.end() ? &preview->second->material : nullptr;
			});

			return material ? material : game::Material_RegisterHandle(name);
		}

		bool decode_preview(const std::string& data, DirectX::ScratchImage& result)
		{
			CoInitializeEx(nullptr, COINIT_MULTITHREADED);

			DirectX::ScratchImage loaded{};
			if (FAILED(DirectX::LoadFromWICMemory(reinterpret_cast<const uint8_t*>(data.data()), data.size(),
				static_cast<DirectX::WIC_FLAGS>(DirectX::WIC_FLAGS_IGNORE_SRGB | DirectX::WIC_FLAGS_FORCE_RGB), nullptr, loaded)))
			{
				return false;
			}

			DirectX::ScratchImage rgba{};
			if (loaded.GetMetadata().format == DXGI_FORMAT_R8G8B8A8_UNORM)
			{
				rgba = std::move(loaded);
			}
			else if (FAILED(DirectX::Convert(*loaded.GetImage(0, 0, 0), DXGI_FORMAT_R8G8B8A8_UNORM, DirectX::TEX_FILTER_DEFAULT,
				DirectX::TEX_THRESHOLD_DEFAULT, rgba)))
			{
				return false;
			}

			const auto& metadata = rgba.GetMetadata();
			const auto largest = std::max(metadata.width, metadata.height);
			if (largest <= max_preview_dimension)
			{
				result = std::move(rgba);
				return true;
			}

			const auto width = std::max<size_t>(1, metadata.width * max_preview_dimension / largest);
			const auto height = std::max<size_t>(1, metadata.height * max_preview_dimension / largest);
			return SUCCEEDED(DirectX::Resize(*rgba.GetImage(0, 0, 0), width, height, DirectX::TEX_FILTER_DEFAULT, result));
		}

		bool create_preview(const std::string& name, const DirectX::ScratchImage& source)
		{
			const auto* white = game::Material_RegisterHandle("white");
			if (!dx::device || !white || !white->textureTable || !white->textureCount || !white->textureTable[0].image)
			{
				return false;
			}

			const auto& base_image = *white->textureTable[0].image;
			const auto format = DirectX::IsSRGB(base_image.imageFormat) ? DXGI_FORMAT_R8G8B8A8_UNORM_SRGB : DXGI_FORMAT_R8G8B8A8_UNORM;
			const auto* image = source.GetImage(0, 0, 0);

			D3D11_TEXTURE2D_DESC desc{};
			desc.Width = static_cast<UINT>(image->width);
			desc.Height = static_cast<UINT>(image->height);
			desc.MipLevels = 1;
			desc.ArraySize = 1;
			desc.Format = format;
			desc.SampleDesc.Count = 1;
			desc.Usage = D3D11_USAGE_IMMUTABLE;
			desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;

			D3D11_SUBRESOURCE_DATA data{};
			data.pSysMem = image->pixels;
			data.SysMemPitch = static_cast<UINT>(image->rowPitch);
			data.SysMemSlicePitch = static_cast<UINT>(image->slicePitch);

			ID3D11Texture2D* texture = nullptr;
			if (FAILED(dx::device->CreateTexture2D(&desc, &data, &texture)))
			{
				return false;
			}

			ID3D11ShaderResourceView* view = nullptr;
			if (FAILED(dx::device->CreateShaderResourceView(texture, nullptr, &view)))
			{
				texture->Release();
				return false;
			}

			auto preview = std::make_unique<preview_t>();
			preview->name = name;

			preview->image = base_image;
			preview->image.texture.map = texture;
			preview->image.texture.shaderView = view;
			preview->image.texture.shaderViewAlternate = nullptr;
			preview->image.imageFormat = format;
			preview->image.dataLen1 = static_cast<unsigned int>(image->slicePitch);
			preview->image.dataLen2 = static_cast<unsigned int>(image->slicePitch);
			preview->image.width = static_cast<unsigned short>(image->width);
			preview->image.height = static_cast<unsigned short>(image->height);
			preview->image.depth = 1;
			preview->image.numElements = 1;
			preview->image.levelCount = 1;
			preview->image.streamed = 0;
			preview->image.pixelData = nullptr;
			std::memset(preview->image.streams, 0, sizeof(preview->image.streams));
			preview->image.name = preview->name.data();

			preview->textures.assign(white->textureTable, white->textureTable + white->textureCount);
			for (auto& texture_def : preview->textures)
			{
				texture_def.image = &preview->image;
			}

			preview->material = *white;
			preview->material.name = preview->name.data();
			preview->material.textureTable = preview->textures.data();

			previews.access([&](std::unordered_map<std::string, std::unique_ptr<preview_t>>& previews_)
			{
				previews_[name] = std::move(preview);
			});

			return true;
		}

		void load_preview(const std::string& id, const std::string& url)
		{
			const auto name = get_preview_name(id);
			if (has_preview(name))
			{
				return;
			}

			const auto data = utils::http::get_data(url, {}, {}, [](const size_t total, const size_t progress)
			{
				return total > max_preview_size || progress > max_preview_size ? -1 : 0;
			});

			if (!data.has_value() || data->code != CURLE_OK || data->response_code >= 400)
			{
				console::warn("Couldn't download the workshop preview for '%s'\n", id.data());
				return;
			}

			auto image = std::make_shared<DirectX::ScratchImage>();
			if (!decode_preview(data->buffer, *image))
			{
				console::warn("Couldn't decode the workshop preview for '%s'\n", id.data());
				return;
			}

			scheduler::once([id, name, image]
			{
				if (!create_preview(name, *image))
				{
					console::warn("Couldn't create the workshop preview for '%s'\n", id.data());
					return;
				}

				scheduler::once([id]
				{
					ui_scripting::notify("workshop_preview",
					{
						{"id", id},
					});
				}, scheduler::pipeline::lui);
			}, scheduler::pipeline::main);
		}

		void notify_refreshed(const std::string& error)
		{
			scheduler::once([error]
			{
				ui_scripting::notify("workshop_refreshed",
				{
					{"error", error},
				});
			}, scheduler::pipeline::lui);
		}
	}

	void refresh()
	{
		if (refreshing.exchange(true))
		{
			return;
		}

		const std::string url = workshop_url ? workshop_url->current.string : "";

		scheduler::once([url]
		{
			const auto _0 = gsl::finally([]
			{
				refreshing = false;
			});

			try
			{
				if (url.empty())
				{
					throw std::runtime_error("Workshop catalog url is not set");
				}

				const auto data = utils::http::get_data(url);
				if (!data.has_value() || data->code != CURLE_OK || data->response_code >= 400)
				{
					throw std::runtime_error(std::format("Couldn't get the workshop catalog from '{}'", url));
				}

				auto result = parse_catalog(data->buffer);
				std::vector<std::pair<std::string, std::string>> images{};
				for (auto& entry : result)
				{
					update_state(entry);
					if (!entry.image.empty())
					{
						images.emplace_back(entry.item.id, entry.image);
					}
				}

				entries.access([&](std::vector<entry_t>& entries_)
				{
					entries_ = std::move(result);
				});

				notify_refreshed("");

				for (const auto& [id, image] : images)
				{
					load_preview(id, image);
				}
			}
			catch (const std::exception& e)
			{
				console::error("%s\n", e.what());
				notify_refreshed(e.what());
			}
		}, scheduler::pipeline::async);
	}

	std::vector<item_t> get_items()
	{
		return entries.access<std::vector<item_t>>([](const std::vector<entry_t>& entries_)
		{
			std::vector<item_t> items{};
			for (const auto& entry : entries_)
			{
				auto item = entry.item;
				const auto name = get_preview_name(item.id);
				item.preview = has_preview(name) ? name : "";
				items.emplace_back(item);
			}

			return items;
		});
	}

	void install(const std::string& id)
	{
		const auto entry = find_entry(id);
		if (!entry.has_value() || entry->files.empty())
		{
			return;
		}

		scheduler::once([entry]
		{
			const auto files = get_outdated_files(entry.value());
			if (files.empty())
			{
				refresh();
				return;
			}

			download::start_download("", files, []
			{
				refresh();
			});
		}, scheduler::pipeline::async);
	}

	void uninstall(const std::string& id)
	{
		const auto entry = find_entry(id);
		if (!entry.has_value() || entry->files.empty())
		{
			return;
		}

		const auto folder = get_folder(entry->item);
		static const auto fs_game = game::Dvar_FindVar("fs_game");
		if (fs_game && utils::string::to_lower(fs_game->current.string) == folder)
		{
			game::shared::menu_error("Unload the mod before uninstalling it.");
			return;
		}

		for (const auto& file : entry->files)
		{
			const auto path = get_path(entry->item, file);
			utils::io::remove_file(path);
			utils::io::remove_file(path + ".tmp");
		}

		if (utils::io::directory_exists(folder) && utils::io::directory_is_empty(folder))
		{
			utils::io::remove_directory(folder);
		}

		refresh();
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			utils::hook::call(0x14061C95E, register_material_stub);

			scheduler::once([]()
			{
				workshop_url = game::Dvar_RegisterString("workshop_url", "", game::DVAR_FLAG_SAVED, "Workshop catalog url");
			}, scheduler::pipeline::main);
		}
	};
}

REGISTER_COMPONENT(workshop::component)
