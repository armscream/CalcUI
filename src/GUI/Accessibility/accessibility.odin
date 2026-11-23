//* The platform bridge for accessibility. The metadata, tree and public API
//* live in Core; this package only registers the native hooks.

package Accessibility

import Core "../Core"

Access_Native :: Core.Access_Native
Access_Tree :: Core.Access_Tree
Access_Node :: Core.Access_Node
Access_Action :: Core.Access_Action
Access_Action_Kind :: Core.Access_Action_Kind

Register :: proc() {
	Core.Access_Use_Native(access_native())
}

//* The platform bridge and the tests use these names.
Access_Available :: proc() -> bool {
	Register()
	return Core.Access_Available()
}
access_allocator :: Core.access_tree_allocator
access_apply_actions :: Core.access_apply_actions
access_node_find_locked :: Core.access_tree_node_find_locked
access_node_of :: Core.access_tree_node_of
access_parent_of :: Core.access_tree_parent_of
access_children_of :: Core.access_tree_children_of
access_tree_destroy :: Core.Access_Tree_Destroy
access_queue_action :: Core.access_queue_action
access_node_added :: Core.access_bridge_node_added
access_node_changed :: Core.access_bridge_node_changed
access_node_removed :: Core.access_bridge_node_removed
access_focus_changed :: Core.access_bridge_focus_changed
access_frame :: Core.access_bridge_frame
