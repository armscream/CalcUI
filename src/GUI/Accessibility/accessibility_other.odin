#+build !windows
package Accessibility

access_native :: proc() -> Access_Native {
	return Access_Native{}
}
