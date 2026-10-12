#pragma once

#include "game/game.hpp"

#include <utils/info_string.hpp>

namespace download
{
	struct file_t
	{
		std::string name;
		std::string hash;
		std::vector<std::string> urls{};
	};

	void start_download(const std::string& base, const std::vector<file_t>& files, const std::function<void()>& callback);
	void stop_download();
}
