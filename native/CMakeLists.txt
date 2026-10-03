cmake_minimum_required(VERSION 3.20)
project(AscentionNative LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
set(REPENTOGON_SOURCE "" CACHE PATH "Matching REPENTOGON source checkout")
set(REPENTOGON_BUILD "" CACHE PATH "Matching REPENTOGON build directory")

foreach(required
    "${REPENTOGON_SOURCE}/include/IsaacRepentance.h"
    "${REPENTOGON_BUILD}/Release/libzhl.lib"
    "${REPENTOGON_BUILD}/Release/Lua5.3.3r.lib")
  if(NOT EXISTS "${required}")
    message(FATAL_ERROR "Missing REPENTOGON build artifact: ${required}")
  endif()
endforeach()

add_library(zhlAscention SHARED src/MiniIsaacWeapon.cpp)
target_include_directories(zhlAscention PRIVATE
  "${REPENTOGON_SOURCE}/include"
  "${REPENTOGON_SOURCE}/libzhl"
  "${REPENTOGON_SOURCE}/libs/lua"
  "${REPENTOGON_SOURCE}/libs/LuaBridge/Source/LuaBridge"
  "${REPENTOGON_SOURCE}/libs/rapidxml"
  "${REPENTOGON_SOURCE}/libs/zydis/include"
  "${REPENTOGON_SOURCE}/libs/zydis/dependencies/zycore/include"
  "${REPENTOGON_SOURCE}/repentogon"
  "${REPENTOGON_SOURCE}/libs/rapidjson/include/rapidjson")
target_compile_options(zhlAscention PRIVATE /EHsc /W4 /wd4251 /wd4996)
target_compile_definitions(zhlAscention PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
target_link_libraries(zhlAscention PRIVATE
  "${REPENTOGON_BUILD}/Release/libzhl.lib"
  "${REPENTOGON_BUILD}/Release/Lua5.3.3r.lib")
set_target_properties(zhlAscention PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
