#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "download.hpp"
#include "console/console.hpp"
#include "scheduler.hpp"

#include "game/ui_scripting/execution.hpp"

#include "utils/hash.hpp"

#include <utils/concurrency.hpp>
#include <utils/http.hpp>
#include <utils/io.hpp>
#include <utils/cryptography.hpp>

namespace download
{
	namespace
	{
		struct globals_t
		{
			bool abort{};
			bool active{};
		};

		std::atomic_bool kill_downloads = false;
		utils::concurrency::container<globals_t> globals;

		bool download_aborted()
		{
			if (kill_downloads)
			{
				return true;
			}

			return globals.access<bool>([](globals_t& globals_)
			{
				return globals_.abort;
			});
		}

		void mark_unactive()
		{
			globals.access([](globals_t& globals_)
			{
				globals_.active = false;
			});
		}

		void mark_active()
		{
			globals.access([](globals_t& globals_)
			{
				globals_.active = true;
			});
		}

		bool download_active()
		{
			return globals.access<bool>([](globals_t& globals_)
			{
				return globals_.active;
			});
		}

		auto last_update = std::chrono::high_resolution_clock::now();
		int progress_callback(size_t total, size_t progress)
		{
			const auto now = std::chrono::high_resolution_clock::now();
			if (now - last_update > 20ms)
			{
				last_update = std::chrono::high_resolution_clock::now();
				auto fraction = 0.f;
				if (total > 0)
				{
					fraction = static_cast<float>(static_cast<double>(progress) /
						static_cast<double>(total));
				}

				scheduler::once([=]
				{
					ui_scripting::notify("mod_download_progress",
					{
						{"fraction", fraction},
					});
				}, scheduler::pipeline::lui);
			}

			//console::debug("Download progress: %lli/%lli\n", progress, total);
			if (download_aborted())
			{
				return -1;
			}

			return 0;
		}

		void menu_error(const std::string& error)
		{
			throw std::runtime_error(error);
		}

		bool download_url(const std::string& url, const std::string& path)
		{
			const auto offset = utils::io::file_size(path);
			console::debug("Downloading %s: %s\n", path.data(), url.data());
			auto data = utils::http::download_to_file(url, path, offset, &progress_callback);
			if (!data.has_value())
			{
				menu_error(utils::string::va("Download failed: An unknown error occurred when getting data from '%s', please try again.", url.data()));
			}

			if (download_aborted())
			{
				return false;
			}

			auto& result = data.value();
			if (result.code != CURLE_OK)
			{
				if (result.code == CURLE_COULDNT_CONNECT)
				{
					menu_error(utils::string::va("Download failed: Couldn't connect to server '%s' (%i)\n",
						url.data(), result.code));
				}

				menu_error(utils::string::va("Download failed: %s (%i)\n",
					curl_easy_strerror(result.code), result.code));
			}

			if (result.response_code >= 400 && !(result.response_code == 416 && offset > 0))
			{
				menu_error(utils::string::va("Download failed: Server returned bad response code (%i)\n",
					result.response_code));
			}

			return true;
		}

		void merge_parts(const std::string& path, const std::vector<std::string>& parts)
		{
			std::ofstream stream(path, std::ios::binary | std::ofstream::out);
			if (!stream.is_open())
			{
				menu_error(utils::string::va("Download failed: Couldn't write file '%s'\n", path.data()));
			}

			std::string buffer;
			buffer.resize(1024 * 1024);

			for (const auto& part : parts)
			{
				std::ifstream part_stream(part, std::ios::binary);
				while (part_stream.read(buffer.data(), buffer.size()) || part_stream.gcount() > 0)
				{
					stream.write(buffer.data(), part_stream.gcount());
				}

				part_stream.close();

				if (!stream.good())
				{
					menu_error(utils::string::va("Download failed: Couldn't write file '%s'\n", path.data()));
				}

				utils::io::remove_file(part);
			}
		}
	}

	void start_download(const std::string& base, const std::vector<file_t>& files, const std::function<void()>& callback)
	{
		if (download_active())
		{
			scheduler::schedule([=]
			{
				if (!download_active())
				{
					start_download(base, files, callback);
					return scheduler::cond_end;
				}

				return scheduler::cond_continue;
			}, scheduler::pipeline::main);

			return;
		}

		globals.access([&](globals_t& globals_)
		{
			globals_ = {};
		});

		scheduler::once([]
		{
			ui_scripting::notify("mod_download_start", {});
		}, scheduler::pipeline::lui);

		scheduler::once([=]
		{
			try
			{
				const auto _0 = gsl::finally(&mark_unactive);
				mark_active();

				if (download_aborted())
				{
					return;
				}

				for (const auto& file : files)
				{
					const auto tmp_name = file.name + ".tmp";
					const auto urls = file.urls.empty()
						? std::vector<std::string>{std::format("{}/{}", base, file.name)}
						: file.urls;

					std::vector<std::string> parts{};
					for (auto i = 0u; i < urls.size(); i++)
					{
						const auto label = urls.size() > 1
							? std::format("{} ({}/{})", file.name, i + 1, urls.size())
							: file.name;

						scheduler::once([=]
						{
							const ui_scripting::table data_table{};
							data_table.set("name", label.data());

							ui_scripting::notify("mod_download_set_file",
							{
								{"request", data_table}
							});
						}, scheduler::pipeline::lui);

						const auto part_name = urls.size() > 1 ? std::format("{}{}", tmp_name, i) : tmp_name;
						if (!download_url(urls[i], part_name))
						{
							return;
						}

						parts.emplace_back(part_name);
					}

					if (parts.size() > 1)
					{
						merge_parts(tmp_name, parts);
					}

					const auto hash = utils::hash::get_file_hash(tmp_name, file.name);
					if (hash != file.hash)
					{
						utils::io::remove_file(tmp_name);
						menu_error(utils::string::va("Download failed: File hash doesn't match the server's (%s: %s != %s)\n",
							file.name.data(), hash.data(), file.hash.data()));
					}

					utils::io::remove_file(file.name);
					if (!utils::io::move_file(tmp_name, file.name))
					{
						menu_error(utils::string::va("Download failed: Couldn't write file '%s'\n", file.name.data()));
					}
				}
			}
			catch (const std::exception& e)
			{
				const std::string error = e.what();
				scheduler::once([error]
				{
					ui_scripting::notify("mod_download_done", {});
					game::shared::menu_error(error);
				}, scheduler::pipeline::lui);
				return;
			}

			scheduler::once([]
			{
				ui_scripting::notify("mod_download_done", {});
			}, scheduler::pipeline::lui);

			scheduler::once(callback, scheduler::pipeline::main);
		}, scheduler::pipeline::async);
	}

	void stop_download()
	{
		if (!download_active())
		{
			return;
		}

		globals.access([&](globals_t& globals_)
		{
			globals_.abort = true;
		});

		scheduler::once([]
		{
			ui_scripting::notify("mod_download_done", {});
			game::shared::menu_error("Download failed: Aborted");
		}, scheduler::pipeline::lui);
	}

	class component final : public component_interface
	{
	public:
		void pre_destroy() override
		{
			kill_downloads = true;
		}
	};
}

REGISTER_COMPONENT(download::component)
