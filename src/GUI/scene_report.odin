//* The report of the scene loader: what is wrong with a scene file, where
//* it is wrong and how bad it is. The loader fills the report as it
//* works, so that a program can say what the file got wrong instead of
//* only saying that it did not load.
//*
//* == Who owns the report ==
//* The report owns the strings of its entries: the message of an entry,
//* the name of the node and the key of the property. They are made in
//* the allocator of the report, and Scene_Report_Destroy gives them
//* back. An entry does not point at the strings of the document, so a
//* report is still good after the document is given back.
//*
//* The list of the entries is the memory of the program, as every list
//* is, and Scene_Report_Destroy gives it back too.

package GUI

import "core:fmt"
import "core:mem"
import "core:strings"

//* How bad a thing in a scene file is. A note only says something, a
//* warning is a thing the loader did not use, and an error is a node that
//* could not be made.
Scene_Severity :: enum {
	Note,
	Warning,
	Error,
}

//* One thing that is wrong with a scene file.
Scene_Diagnostic :: struct {
	severity: Scene_Severity,
	//* The line of the file the thing is on. The first line of the file
	//* is line 1.
	line:     int,
	//* The name of the node the thing is about. It is empty when the
	//* thing is not about a node.
	node:     string,
	//* The key of the property the thing is about. It is empty when the
	//* thing is not about a property.
	property: string,
	//* What is wrong, said in a way that can be shown to a person.
	message:  string,
}

//* The things that are wrong with a scene file. The report owns the
//* strings of the entries: they live in the allocator of the report and
//* Scene_Report_Destroy gives them back.
//
//* The allocator is in the report, so that the strings can be given back.
//* A report that was made without one gets the allocator of the program
//* when an entry is put in it.
Scene_Report :: struct {
	entries:  [dynamic]Scene_Diagnostic,
	allocator: mem.Allocator,
}

//* Gives the memory of a report back: the strings of every entry and
//* the list of the entries.
//
//* The report owns the strings of the entries, so they are given back
//* with the allocator of the report. A report that was made without an
//* allocator has no strings of its own.
Scene_Report_Destroy :: proc(report: ^Scene_Report) {
	if report == nil {return}
	allocator := report.allocator
	if allocator.procedure != nil {
		for &entry in report.entries {
			delete(entry.node, allocator)
			delete(entry.property, allocator)
			delete(entry.message, allocator)
		}
	}
	delete(report.entries)
	report.entries = nil
	report.allocator = mem.Allocator{}
}

//* The allocator of the report. A report that was made without one gets
//* the allocator of the program, so that its strings are given back.
scene_report_allocator :: proc(report: ^Scene_Report) -> mem.Allocator {
	if report == nil {return context.allocator}
	if report.allocator.procedure == nil {
		report.allocator = context.allocator
	}
	return report.allocator
}

//* Puts a thing that is wrong with a scene file in the report. The
//* message is made in the allocator of the report, and the name of the
//* node and the key of the property are copied into it, so that the
//* report does not point at the strings of the document.
scene_report_add :: proc(
	report: ^Scene_Report,
	severity: Scene_Severity,
	line: int,
	node: string,
	property: string,
	format: string,
	args: ..any,
) {
	if report == nil {return}
	message := fmt.aprintf(format, ..args, allocator = scene_report_allocator(report))
	scene_report_add_message(report, severity, line, node, property, message)
}

//* Puts a thing that is wrong with a scene file in the report. The
//* message is the text that is given: it is made in the allocator of the
//* report, and the report owns it.
scene_report_add_message :: proc(
	report: ^Scene_Report,
	severity: Scene_Severity,
	line: int,
	node: string,
	property: string,
	message: string,
) {
	if report == nil {return}
	allocator := scene_report_allocator(report)
	append(&report.entries, Scene_Diagnostic {
		severity = severity,
		line     = line,
		node     = strings.clone(node, allocator),
		property = strings.clone(property, allocator),
		message  = message,
	})
}

//* Whether the report holds an error. A scene file with an error in it
//* is not a scene file that can be trusted.
Scene_Report_Has_Errors :: proc(report: ^Scene_Report) -> bool {
	if report == nil {return false}
	for entry in report.entries {
		if entry.severity == .Error {return true}
	}
	return false
}

//* Puts the things of one report into another. The entries move with the
//* strings that belong to them, so they are given back once: by the
//* report that holds them in the end.
//
//* The two reports must have the same allocator, or the strings are
//* given back with the wrong one.
scene_report_merge :: proc(report: ^Scene_Report, other: ^Scene_Report) {
	if report == nil || other == nil {return}
	for entry in other.entries {
		append(&report.entries, entry)
	}
	//* The report that gave the entries away has none of them now.
	delete(other.entries)
	other.entries = nil
	other.allocator = mem.Allocator{}
}

//* The name of a severity, as it is written in the report.
scene_severity_name :: proc(severity: Scene_Severity) -> string {
	switch severity {
	case .Note:
		return "note"
	case .Warning:
		return "warning"
	case .Error:
		return "error"
	}
	return "note"
}

//* The report as text: one line for each thing that is wrong, of the
//* shape `scene:12: error: the parent "X" of the node "Y" is not in the
//* file`. The text is made in the allocator that is given, and the caller
//* gives it back with `delete`.
Scene_Report_To_String :: proc(report: ^Scene_Report, allocator: mem.Allocator) -> string {
	if report == nil {return ""}
	builder: strings.Builder
	if _, err := strings.builder_init_len_cap(&builder, 0, 256, allocator); err != nil {
		return ""
	}
	for entry in report.entries {
		strings.write_string(&builder, "scene:")
		strings.write_int(&builder, entry.line)
		strings.write_string(&builder, ": ")
		strings.write_string(&builder, scene_severity_name(entry.severity))
		strings.write_string(&builder, ": ")
		strings.write_string(&builder, entry.message)
		strings.write_byte(&builder, '\n')
	}
	return strings.to_string(builder)
}
