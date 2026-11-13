package GUI

CALCUI_VERSION :: "0.1.0"
CALCUI_API_VERSION :: 1
MIN_ODIN_VERSION :: "dev-2026-10"

Version :: proc() -> string {
	return CALCUI_VERSION
}

API_Version :: proc() -> int {
	return CALCUI_API_VERSION
}

//* Checks whether the toolkit supports the requested API version.
Is_Compatible :: proc(api: int) -> bool {
	return api <= CALCUI_API_VERSION
}