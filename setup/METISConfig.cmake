get_filename_component (_IMPORT_PREFIX "${CMAKE_CURRENT_LIST_FILE}" PATH)
set (_IMPORT_PREFIX "${_IMPORT_PREFIX}")

add_library (METIS SHARED IMPORTED)
set_target_properties (METIS PROPERTIES
		INTERFACE_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include"
		IMPORTED_CONFIGURATIONS "RELEASE"
		IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "C"
		IMPORTED_IMPLIB_RELEASE "${_IMPORT_PREFIX}/lib/metis.lib"
		IMPORTED_LOCATION "${_IMPORT_PREFIX}/metis.dll"
		MAP_IMPORTED_CONFIG_RELWITHDEBINFO Release
		MAP_IMPORTED_CONFIG_MINSIZEREL Release
		)
		
#LIST (APPEND CMAKE_PREFIX_PATH "${LIBS_BUNDLE}")
#set (CMAKE_FIND_PACKAGE_PREFER_CONFIG TRUE)