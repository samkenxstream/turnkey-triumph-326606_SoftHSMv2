include(CheckCXXCompilerFlag)
include(CheckFunctionExists)
include(CheckIncludeFiles)
include(CheckLibraryExists)
include(CheckSymbolExists)
include(CheckTypeSize)

function(enable_cxx_compiler_flag_if_supported flag)
    string(FIND "${CMAKE_CXX_FLAGS}" "${flag}" flag_already_set)
    if(flag_already_set EQUAL -1)
        check_cxx_compiler_flag("${flag}" flag_supported)
        if(flag_supported)
            add_compile_options(${flag})
        elseif(flag_supported)
            message(WARNING "unsupported compiler flag: ${flag}")
        endif(flag_supported)
        unset(flag_supported CACHE)
    endif()
endfunction()

# Configures C++11
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED 1)
set(HAVE_CXX11 1)

if(ENABLE_PEDANTIC)
    enable_cxx_compiler_flag_if_supported(-pedantic)
    set(ENABLE_STRICT ON)
endif(ENABLE_PEDANTIC)

if(ENABLE_STRICT)
    set(CMAKE_CXX_EXTENSIONS OFF)
endif(ENABLE_STRICT)

if(ENABLE_SHARED)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif(ENABLE_SHARED)

# Compiler Options/Macros

# FIXME: These options need to be set on a per object file basis (*.o). Do not belong here.
#        Are these even required? They just modify the Makefile representation of the target.
#add_compile_options(-MD)
#add_compile_options(-MP)
#add_compile_options(-MF)
#add_compile_options(-MT)

# FIXME: [Implement AC_HEADER_STDC]:
# Find a CMake mechanism performs the check as defined in
# AC_HEADER_STDC:
# https://www.gnu.org/software/autoconf/manual/autoconf-2.67/html_node/Particular-Headers.html
#
# Not sure if this is a legacy check, or it's something that we need to
# continue to check with modern compiler versions.
set(STDC_HEADERS 1)

# acx_strict.m4
if(ENABLE_STRICT)
    enable_cxx_compiler_flag_if_supported(-Wall)
    enable_cxx_compiler_flag_if_supported(-Wextra)
endif(ENABLE_STRICT)

# acx_64bit.m4
if(ENABLE_64BIT)
    if(CMAKE_SIZEOF_VOID_P STREQUAL "8")
        set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -m64")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -m64")
    else(CMAKE_SIZEOF_VOID_P STREQUAL "8")
        set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -m32")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -m32")
    endif(CMAKE_SIZEOF_VOID_P STREQUAL "8")
endif(ENABLE_64BIT)

# Equivalent of acx_visibility.m4
if(DISABLE_VISIBILITY)
    message(STATUS "-fvisibility=hidden has been disabled")
else(DISABLE_VISIBILITY)
    set(CRYPTOKI_VISIBILITY 1)
    set(CMAKE_CXX_VISIBILITY_PRESET hidden)
endif(DISABLE_VISIBILITY)

# acx_non_paged_memory.m4
if(DISABLE_NON_PAGED_MEMORY)
    message(STATUS "non-paged-memory disabled")
else(DISABLE_NON_PAGED_MEMORY)
    set(SENSITIVE_NON_PAGE 1)
    check_include_files(sys/mman.h HAVE_SYS_MMAN_H)
    execute_process(COMMAND bash -c "ulimit -l"
                    OUTPUT_VARIABLE MLOCK_SIZE
                    OUTPUT_STRIP_TRAILING_WHITESPACE
                    )
    if(NOT "${MLOCK_SIZE}" STREQUAL "unlimited")
        message(WARNING "\
    ======================================================================
    SoftHSM has been configured to store sensitive data in non-page RAM
    (i.e. memory that is not swapped out to disk). This is the default and
    most secure configuration. Your system, however, is not configured to
    support this model in non-privileged accounts (i.e. user accounts).

    You can check the setting on your system by running the following
    command in a shell:

            ulimit -l

    If this does not return \"unlimited\" and you plan to run SoftHSM from
    non-privileged accounts then you should edit the configuration file
    /etc/security/limits.conf (on most systems).

    You will need to add the following lines to this file:

    #<domain>       <type>          <item>          <value>
    *               -               memlock         unlimited

    Alternatively, you can elect to disable this feature of SoftHSM by
    re-running cmake with the option \"-DDISABLE_NON_PAGED_MEMORY=ON\".
    Please be advised that this may seriously degrade the security of
    SoftHSM.
    ======================================================================")
    endif(NOT "${MLOCK_SIZE}" STREQUAL "unlimited")
endif(DISABLE_NON_PAGED_MEMORY)

# Check if -ldl exists (equivalent of acx_dlopen.m4)
check_library_exists(dl dlopen "" HAVE_DLOPEN)
check_function_exists(LoadLibrary HAVE_LOADLIBRARY)

# acx_libtool.m4
check_include_files(dlfcn.h HAVE_DLFCN_H)

# configure:

# STDC_HEADERS
check_include_files(sys/types.h HAVE_SYS_TYPES_H)
check_include_files(sys/stat.h HAVE_SYS_STAT_H)
check_include_files(stdlib.h HAVE_STDLIB_H)
check_include_files(stddef.h HAVE_STDDEF_H)
check_include_files(string.h HAVE_STRING_H)
check_include_files(strings.h HAVE_STRINGS_H)
check_include_files(inttypes.h HAVE_INTTYPES_H)
check_include_files(stdint.h HAVE_STDINT_H)
check_include_files(unistd.h HAVE_UNISTD_H)

check_include_files(memory.h HAVE_MEMORY_H)
check_include_files(pthread.h HAVE_PTHREAD_H)
check_function_exists(getpwuid_r HAVE_GETPWUID_R)

# Find Botan Crypto Backend (equivalent of acx_botan.m4)
if(WITH_BOTAN)
    include(FindBotan)
    if(BOTAN_FOUND)
        message(STATUS "Found Botan")
        set(CRYPTO_INCLUDES ${BOTAN_INCLUDE_DIRS})
        set(CRYPTO_LIBS ${BOTAN_LIBRARIES})
    else(BOTAN_FOUND)
        message(FATAL_ERROR "Failed to find Botan!")
    endif(BOTAN_FOUND)
endif(WITH_BOTAN)

# Find OpenSSL Crypto Backend (equivalent of acx_crypto_backend.m4)
if(WITH_OPENSSL)
    include(FindOpenSSL)
    if(OPENSSL_FOUND)
        set(CRYPTO_INCLUDES ${OPENSSL_INCLUDE_DIR})
        set(CRYPTO_LIBS ${OPENSSL_LIBRARIES})
        message(STATUS "OpenSSL: Found version ${OPENSSL_VERSION}")
        message(STATUS "OpenSSL: Includes: ${CRYPTO_INCLUDES}")
        message(STATUS "OpenSSL: Libs: ${CRYPTO_LIBS}")

        # Compile with RAW PKCS PSS
        set(WITH_RAW_PSS 1)
        # Compile with AES_GCM
        set(WITH_AES_GCM 1)

        check_include_files(openssl/ssl.h HAVE_OPENSSL_SSL_H)

        get_filename_component(CRYPTO_LIB_DIR "${OPENSSL_CRYPTO_LIBRARY}" DIRECTORY)
        check_library_exists(crypto "BN_new" "${CRYPTO_LIB_DIR}" HAVE_LIBCRYPTO)

        # acx_openssl_ecc.m4
        if(ENABLE_ECC)
            set(testfile ${CMAKE_SOURCE_DIR}/modules/tests/test_openssl_ecc.c)
            try_run(RUN_ECC COMPILE_RESULT
                    "${CMAKE_BINARY_DIR}/prebuild_santity_tests" ${testfile}
                    LINK_LIBRARIES ${CRYPTO_LIBS}
                    CMAKE_FLAGS
                        "-DINCLUDE_DIRECTORIES=${CRYPTO_INCLUDES}"
                    )
            if(COMPILE_RESULT AND RUN_ECC EQUAL 0)
                set(WITH_ECC 1)
                message(STATUS "OpenSSL: Found P-256, P-384, and P-521")
            else()
                set(error_msg "OpenSSL: Cannot find P-256, P-384, or P-521! OpenSSL library has no ECC support!")
                message(FATAL_ERROR ${error_msg})
            endif()
        else(ENABLE_ECC)
            message(STATUS "OpenSSL: Support for ECC is disabled")
        endif(ENABLE_ECC)

        # acx_openssl_eddsa.m4
        if(ENABLE_EDDSA)
            # ED25519
            set(testfile ${CMAKE_SOURCE_DIR}/modules/tests/test_openssl_ed25519.c)
            try_run(RUN_ED25519 COMPILE_RESULT
                    "${CMAKE_BINARY_DIR}/prebuild_santity_tests" ${testfile}
                    LINK_LIBRARIES ${CRYPTO_LIBS}
                    CMAKE_FLAGS
                        "-DINCLUDE_DIRECTORIES=${CRYPTO_INCLUDES}"
                    )
            if(COMPILE_RESULT AND RUN_ED25519 EQUAL 0)
                set(WITH_EDDSA 1)
                message(STATUS "OpenSSL: Found ED25519")
            else()
                set(error_msg "OpenSSL: Cannot find ED25519! OpenSSL library has no EDDSA support!")
                message(FATAL_ERROR ${error_msg})
            endif()
            # ED448
            set(testfile ${CMAKE_SOURCE_DIR}/modules/tests/test_openssl_ed448.c)
            try_run(RUN_ED448 COMPILE_RESULT
                    "${CMAKE_BINARY_DIR}/prebuild_santity_tests" ${testfile}
                    LINK_LIBRARIES ${CRYPTO_LIBS}
                    CMAKE_FLAGS
                        "-DINCLUDE_DIRECTORIES=${CRYPTO_INCLUDES}"
                    )
            if(COMPILE_RESULT AND RUN_ED448 EQUAL 0)
                message(STATUS "OpenSSL: Found ED448")
            else()
                # Not used in SoftHSM
                message(STATUS "OpenSSL: Cannot find ED448!")
            endif()
        else(ENABLE_EDDSA)
            message(STATUS "OpenSSL: Support for EDDSA is disabled")
        endif(ENABLE_EDDSA)

        # acx_openssl_gost.m4
        if(ENABLE_GOST)
            set(testfile ${CMAKE_SOURCE_DIR}/modules/tests/test_openssl_gost.c)
            try_run(RUN_GOST COMPILE_RESULT
                    "${CMAKE_BINARY_DIR}/prebuild_santity_tests" ${testfile}
                    LINK_LIBRARIES ${CRYPTO_LIBS}
                    CMAKE_FLAGS
                        "-DINCLUDE_DIRECTORIES=${CRYPTO_INCLUDES}"
                    )
            if(COMPILE_RESULT AND RUN_GOST EQUAL 0)
                set(WITH_GOST 1)
                message(STATUS "OpenSSL: Found GOST engine")
            else()
                set(error_msg "OpenSSL: Cannot find GOST engine! OpenSSL library has no GOST support!")
                message(FATAL_ERROR ${error_msg})
            endif()
        else(ENABLE_GOST)
            message(STATUS "OpenSSL: Support for GOST is disabled")
        endif(ENABLE_GOST)

        # acx_openssl_fips.m4
        if(ENABLE_FIPS)
            set(testfile ${CMAKE_SOURCE_DIR}/modules/tests/test_openssl_fips.c)
            try_run(RUN_FIPS COMPILE_RESULT
                    "${CMAKE_BINARY_DIR}/prebuild_santity_tests" ${testfile}
                    LINK_LIBRARIES ${CRYPTO_LIBS}
                    CMAKE_FLAGS
                        "-DINCLUDE_DIRECTORIES=${CRYPTO_INCLUDES}"
                    )
            if(COMPILE_RESULT AND RUN_FIPS EQUAL 0)
                set(WITH_FIPS 1)
                message(STATUS "OpenSSL: Found working FIPS_mode_set()")
            else()
                set(error_msg "OpenSSL: FIPS_mode_set(1) failed. OpenSSL library is not FIPS capable!")
                message(FATAL_ERROR ${error_msg})
            endif()
        else(ENABLE_FIPS)
            message(STATUS "OpenSSL: Support for FIPS 140-2 mode is disabled")
        endif(ENABLE_FIPS)

        # acx_openssl_rfc3349
        set(testfile ${CMAKE_SOURCE_DIR}/modules/tests/test_openssl_rfc3394.c)
        try_run(RUN_AES_KEY_WRAP COMPILE_RESULT
                "${CMAKE_BINARY_DIR}/prebuild_santity_tests" ${testfile}
                LINK_LIBRARIES ${CRYPTO_LIBS}
                CMAKE_FLAGS
                    "-DINCLUDE_DIRECTORIES=${CRYPTO_INCLUDES}"
                )
        if(COMPILE_RESULT AND RUN_AES_KEY_WRAP EQUAL 0)
            set(HAVE_AES_KEY_WRAP 1)
            message(STATUS "OpenSSL: RFC 3394 is supported")
        else()
            message(STATUS "OpenSSL: RFC 3394 is not supported")
        endif()

        # acx_openssl_rfc5649
        set(testfile ${CMAKE_SOURCE_DIR}/modules/tests/test_openssl_rfc5649.c)
        try_run(RUN_AES_KEY_WRAP_PAD COMPILE_RESULT
                "${CMAKE_BINARY_DIR}/prebuild_santity_tests" ${testfile}
                LINK_LIBRARIES ${CRYPTO_LIBS}
                CMAKE_FLAGS
                    "-DINCLUDE_DIRECTORIES=${CRYPTO_INCLUDES}"
                )
        if(COMPILE_RESULT AND RUN_AES_KEY_WRAP_PAD EQUAL 0)
            set(HAVE_AES_KEY_WRAP_PAD 1)
            message(STATUS "OpenSSL: RFC 5649 is supported")
        else()
            message(STATUS "OpenSSL: RFC 5649 is not supported")
        endif()

    else(OPENSSL_FOUND)
        message(FATAL_ERROR "Failed to find OpenSSL!")
    endif(OPENSSL_FOUND)
endif(WITH_OPENSSL)

# Find SQLite3
if(WITH_SQLITE3)
    include(FindSQLite3)
    if(SQLITE3_FOUND)
        message(STATUS "Found SQLite3")
        set(SQLITE3_INCLUDES ${SQLITE3_INCLUDE_DIRS})
        set(SQLITE3_LIBS ${SQLITE3_LIBRARIES})
        check_include_files(sqlite3.h HAVE_SQLITE3_H)
        check_library_exists(sqlite3 sqlite3_prepare_v2 "" HAVE_LIBSQLITE3)
        find_program(SQLITE3_COMMAND NAMES sqlite3)
        if(SQLITE3_COMMAND MATCHES "-NOTFOUND")
            message(FATAL_ERROR "sqlite3 command was not found")
        endif(SQLITE3_COMMAND MATCHES "-NOTFOUND")
    else(SQLITE3_FOUND)
        message(FATAL_ERROR "Failed to find SQLite3!")
    endif(SQLITE3_FOUND)
endif(WITH_SQLITE3)

if(BUILD_TESTS)
    # Find CppUnit (equivalent of acx_cppunit.m4)
    include(FindCppUnit)
    if(CPPUNIT_FOUND)
        message(STATUS "Found CppUnit")
        set(CPPUNIT_INCLUDES ${CPPUNIT_INCLUDE_DIR})
        set(CPPUNIT_LIBS ${CPPUNIT_LIBRARY})
    else(CPPUNIT_FOUND)
        message(FATAL_ERROR "Failed to find CppUnit!")
    endif(CPPUNIT_FOUND)
endif(BUILD_TESTS)

configure_file(config.h.in.cmake ${CMAKE_BINARY_DIR}/config.h)
