#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dir="$project_dir/.build/smoke-tests"

mkdir -p "$output_dir"
swiftc \
  "$project_dir/Sources/MetridayApp/Models.swift" \
  "$project_dir/Sources/MetridayApp/TrackingDay.swift" \
  "$project_dir/Sources/MetridayApp/ProjectTracking.swift" \
  "$project_dir/Sources/MetridayApp/TeamStore.swift" \
  "$project_dir/Sources/MetridayApp/TimeEntryStore.swift" \
  "$project_dir/Sources/MetridayApp/TimeBlockExecution.swift" \
  "$project_dir/Sources/MetridayApp/PreferencesStore.swift" \
  "$project_dir/Sources/MetridayApp/CalendarEventStore.swift" \
  "$project_dir/Sources/MetridayApp/Theme.swift" \
  "$project_dir/Sources/MetridayApp/TimelineComponents.swift" \
  "$project_dir/Sources/MetridayApp/CalendarEventTimeline.swift" \
  "$project_dir/Sources/MetridayApp/PhoneCallStore.swift" \
  "$project_dir/Sources/MetridayApp/ReminderStore.swift" \
  "$project_dir/Sources/MetridayApp/ScreenTimeStore.swift" \
  "$project_dir/Sources/MetridayApp/ActivityInsights.swift" \
  "$project_dir/Sources/MetridayApp/ExclusionStore.swift" \
  "$project_dir/Sources/MetridayApp/ReportExporter.swift" \
  "$project_dir/Sources/MetridayApp/XLSXReportWriter.swift" \
  "$project_dir/Sources/MetridayApp/PDFReportWriter.swift" \
  "$project_dir/Sources/MetridayApp/ActivityTracking.swift" \
  "$project_dir/Sources/MetridayApp/AppActivityMonitor.swift" \
  "$project_dir/Sources/MetridayApp/ActivityFilterStore.swift" \
  "$project_dir/Sources/MetridayApp/ActivityCategoryStore.swift" \
  "$project_dir/Sources/MetridayApp/ActivitiesPreferencesStore.swift" \
  "$project_dir/Sources/MetridayApp/WebBlockerService.swift" \
  "$project_dir/Sources/MetridayApp/SyncStore.swift" \
  "$project_dir/Sources/MetridayApp/LocalAPIServer.swift" \
  "$project_dir/Sources/MetridayApp/MarkdownCodec.swift" \
  "$project_dir/Sources/MetridayApp/MarkdownStore.swift" \
  "$project_dir/SmokeTests/main.swift" \
  -framework AppKit \
  -framework SwiftUI \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -framework EventKit \
  -framework Network \
  -o "$output_dir/MetridaySmokeTests"
"$output_dir/MetridaySmokeTests"
