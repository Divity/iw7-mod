#pragma once

namespace utils::hash
{
	std::string get_file_hash(const std::string& file);
	std::string get_file_hash(const std::string& file, const std::string& filename);
}
