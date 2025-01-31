cmake_minimum_required(VERSION 3.13)
project(BufferTest CXX)

# Add option for using Clang
option(USE_CLANG "Build with clang" ON)

# Set compiler to Clang if USE_CLANG is ON
if(USE_CLANG)
    set(CMAKE_CXX_COMPILER clang++)
endif()

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -frtti")

# enable limited API

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DPy_LIMITED_API=0x03090000")

# Add max warning flags
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wcast-qual -Wformat=2 -Wundef -Werror=float-equal -Wshadow -Wcast-align -Wunused -Wnull-dereference -Wdouble-promotion -Wimplicit-fallthrough -Wextra-semi -Woverloaded-virtual -Wnon-virtual-dtor ")
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra")
endif()

# (Set SWIG policies if needed)
if (POLICY CMP0078)
  cmake_policy(SET CMP0078 NEW)
endif()
if (POLICY CMP0086)
  cmake_policy(SET CMP0086 NEW)
endif()

find_package(SWIG REQUIRED)
include(UseSWIG)

find_package(Python3 COMPONENTS Interpreter Development REQUIRED)

set(CMAKE_SWIG_FLAGS "-c++" 
  "-Wextra"     
  "-Wall"
  "-threads" )
set_source_files_properties(src/buffer_interface.i PROPERTIES CPLUSPLUS ON USE_SWIG_DEPENDENCIES TRUE)

swig_add_library(
  buffer_interface
  TYPE MODULE           
  LANGUAGE Python
  SOURCES src/buffer_interface.i
)

swig_link_libraries(buffer_interface PRIVATE ${Python3_LIBRARIES})
target_include_directories(buffer_interface PRIVATE ${Python3_INCLUDE_DIRS} ${CMAKE_CURRENT_SOURCE_DIR}/src)

# If you do NOT need to link the extension into your test, just remove
# the linking below -- a MODULE is not meant for direct linking.
# 
# Instead you can build a separate test or skip it entirely
# if the only purpose is to run Python code.

# For a pure Python test, you can just do:
#   python3 src/test_buffer_interface.py
