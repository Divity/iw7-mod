#pragma once

namespace workshop
{
	struct item_t
	{
		std::string id;
		std::string type;
		std::string name;
		std::string author;
		std::string description;
		std::string version;
		std::uint64_t size{};
		std::string state;
		std::string preview;
	};

	void refresh();
	std::vector<item_t> get_items();
	void install(const std::string& id);
	void uninstall(const std::string& id);
}
