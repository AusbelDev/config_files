---
name: kimai-management
description: Comprehensive management of Kimai time-tracking and Outlook calendar synchronization. Trigger this skill whenever a user mentions syncing meetings, logging time, importing calendar events, or managing Kimai projects and activities. It handles user profile storage, schedules, lunch configurations, project nomenclature, teammate mappings, and deletes logs safely.
---

# Kimai Management Skill

This skill facilitates the usage of the Kimai MCP tools to manage time-tracking, calendar synchronization, and profile-based automation.

## Core Workflows

### 0. Workflow Ordering for Kimai Operations
For EVERY single Kimai operation (including exporting PDFs, syncing meetings, filling timesheets, deleting timesheets, or listing resources/recent entries), the agent **MUST ALWAYS** first fetch and verify the user profile with the `kimai_get_user_profile` tool to apply any user prompts and settings. If no profile exists yet (a fresh setup), run the bootstrap in Section 1 first — download the server metadata with `context_download`, then initialize and interview — before attempting the operation.

Whenever a user asks for filling, syncing, or creating timesheets within a period of time, the agent **MUST** perform the operations in the following order:
1. **Fetch and Verify Profile**: Retrieve the user profile and ensure it is in a valid, not-expired state. **CRITICAL**: If `meetings_map`, `user_prompts`, or teammates are empty, you **MUST** run the validation setup immediately (see Section 1 and 3) to interview the user, construct these configurations, and save the updated profile via `save_user_profile` *before* continuing.
2. **Get Available Time slots**: Call `get_available_times_in_range` within the user-provided date range to find open slots.
3. **Sync Meetings First**: Pull Outlook meetings via the mapping rules. If any meetings are missing project data, sync the ones that are clear first, then ask the user to pinpoint which projects the ambiguous meetings belong to.
4. **Get Available Time slots Again**: Refresh available time ranges after meetings are successfully synced.
5. **Create Requested Timesheets**: Generate the remaining timesheet entries in the open time blocks, following all scheduling constraints (Section 4).


### 1. User Profile Setup & Validation (Pre-flight)
Before processing ANY Kimai request or operation (including sync, time-tracking, PDF exports, listings, and deletions), the agent **MUST ALWAYS** fetch/retrieve the user profile:
1. **Verify Profile Expiration**: Call the tool `expired_profile_data` (or `kimai_expired_profile_data`). This tells you whether a profile exists at all, is fresh, or has expired:
   - `"Non existing profile data. Must ask the user for it"` → this is a **fresh setup**. Follow the "Fresh Setup" bootstrap below before anything else.
   - `"Profile expired, needs reloading"` → the profile exists but is stale; refresh the server metadata (see Fresh Setup step A) so newly-added projects/activities are picked up, then re-interview only for whatever is missing.
   - `"Profile updated: ..."` → the profile is current; skip to the operation, loading it as normal.

   **Fresh Setup (no profile exists yet) — bootstrap the metadata first.** The profile is auto-initialized from locally cached Kimai metadata (customers, projects, activities). On a brand-new machine those local files don't exist yet, and trying to initialize the profile before they're present will fail. So on a fresh setup:
   - **A. Download server metadata**: Call `context_download` (`kimai_context_download`) to pull customers, projects, activities, timesheets, and tags from the Kimai server into the local context cache. Without this, profile initialization has nothing to map and will error.
   - **B. Initialize the skeleton profile**: Now retrieve the profile (see step 2). It comes back pre-populated with the customer/project/activity tree from the server, but with empty `duty_schedule`, `lunch_times`, `teammates`, `meetings_map`, `user_prompts`, and `report_config`.
   - **C. Interview to fill the blanks**: Walk the user through step 3 below to complete those empty sections, then save (step 4).
2. **Retrieve or Initialize Profile**:
   - Access/read the profile via the `file://kimai_user_profile.json` resource (or the `kimai_get_user_profile` tool).
   - If the profile is missing or expired, this returns a freshly initialized profile with projects, customers, and activities automatically mapped from the cached server metadata. (On a fresh setup, make sure you have run `context_download` first — see the Fresh Setup bootstrap above — otherwise there is no metadata to map and initialization fails.)
3. **Interview for Missing Details**: If any details are missing or empty, ask the user sequentially following these exact steps:
   * **Step 1 (duty_schedule)**: If missing, ask the user for their working hours/duty schedule.
   * **Step 2 (lunch_times)**: If missing, ask the user for their lunch times.
   * **Step 3 (teammates)**: If missing, complete the teammates properties of the projects:
     1. Fetch meeting participants for the present week with the tool `get_meeting_participants`.
     2. Ask the user which participants belong to which project (normally, all meeting participants are teammates).
   * **Step 4 (meetings_map)**: Ask the user to map the meetings to their corresponding projects:
     1. List projects to show the user.
     2. Propose some logical mappings to facilitate the user's input.
   * **Step 5 (other_instructions)**: Ask the user if they have other instructions (e.g. project manager guidelines, specific mapping rules) that should be recorded.
   * **Step 6 (report_config)**: If `report_config` is missing or empty, ask the user for:
     - The boss's email address (for weekly report recipients, and carbon copy on monthly reports).
     - The HR office's email address (for monthly report recipients).
     - Build the configuration mapping under `"weekly"` (recipient: boss, CC: empty) and `"monthly"` (recipient: HR, CC: boss).
   * **Step 7 (scheduled_tasks)**: If `enabled_scheduled` is true and `scheduled_tasks` is empty, ask the user if they want to configure task scheduling (e.g., automated weekly/monthly exports and report emails).
     - If the user explicitly declines scheduling, update the profile to set `enabled_scheduled: false` to prevent future prompts.
     - If they accept, ask for their preferred schedule/times (e.g. day of week, day of month, specific time) and configure the `scheduled_tasks` list accordingly.
     - Try to register the corresponding cron jobs using the background `schedule` tool if the system is configured to support it. If scheduling triggers/cron capability is not fully supported or is denied by permissions, clearly warn the user about it.
4. **Save Profile**: Save the updated configuration by calling the tool `save_user_profile` (or `kimai_save_user_profile`).

### 2. Project Mapping Nomenclature
Kimai projects follow a structured nomenclature which must be parsed accurately:
- Example: `EXT-JEP-AMX-PRJ-FP-Atrium Implementation JOC/JTA`
- Structure: `[INTERNAL/EXTERNAL] - [DEVELOPMENT_TYPE] - [CUSTOMER_ABBR] - [PRJ] - [FP] - [PROJECT_NAME]`
  - `EXT` / `INT`: External (billable to customer) or Internal indicator.
  - `JEP` / `OPT`: Indicates a Jeppesen partner project or an internally developed Optimen project.
  - `CUSTOMER_ABBR` / `PROJECT_NAME`: Used to map items to the user profile's internal representation.

*Activity Rules:*
- **External**: Almost all coding/testing activities are external (billable) unless told otherwise.
- **Internal**: Researching, training, administrative, and almost all meetings are internal (non-billable) unless explicitly said.
- **Fallbacks**: If context is missing, fetch metadata via the API (or local JSON files) and resolve manually.

### 3. Teammates, Meetings, and Prompts Setup
If teammate or meeting mapping data is missing from a customer or project in the profile:
1. **Fetch Participants**: Fetch the current week's meetings via `get_outlook_events` and extract attendees and organizers using `get_meeting_participants`.
2. **Associate Teammates**: Present the list of participants or ask the user for their teammate email addresses. Save this mapping in the Customer's `teammates` list (`current_projects[CUSTOMER_ABBR].teammates`). These teammate lists are used during meeting sync to automatically assign events to the correct customer if the attendees match.
3. **Map Meetings to Projects**: Ask the user which meetings correspond to which projects and record this mapping.
4. **Agent Prompts**: Ask the user relevant preference questions to facilitate sync tasks. Convert their answers into concise agent prompts and append them to the `user_prompts` array in the profile. Inject these prompts dynamically into your context during future operations.
   - *Dynamic Prompts Update*: Whenever the user asks to update their profile or prompts:
     1. Load the current user profile from `file://kimai_user_profile.json` (do not start from scratch).
     2. **CRITICAL PRESERVATION RULE**: The agent **MUST NEVER** overwrite, erase, or nullify existing profile properties (like `current_projects`, `duty_schedule`, `lunch_times`, or `meetings_map`) unless explicitly requested by the user. Keep all properties intact while appending/modifying. If the agent accidentally erases properties, they **MUST** immediately apologize to the user and guide them through completing the missing profile information.
     3. Parse the request, compress it to an equivalent agent-friendly, low-token cost prompt.
     4. Append/insert this prompt into the `user_prompts` array.
     5. Save the updated profile using the `save_user_profile` tool.
   - *Pre-Execution Loading*: In EVERY Kimai operation, the agent **MUST** load the user profile (via the `file://kimai_user_profile.json` resource or the `kimai_get_user_profile` tool) to read and strictly apply the latest preferences defined in `user_prompts`, injecting these custom prompts to facilitate the tasks requested by the user.

### 4. Timesheet Generation & Scheduling Rules
When generating timesheets from Outlook events, you must apply the profile's schedule constraints:
1. **Duty Bound**: Ensure timesheet entries start no earlier than `duty_schedule.start` and end no later than `duty_schedule.end` for that weekday.
   - *Weekday Resolving Priority*: When checking duty hours and lunch breaks for a specific day of the week, first check for an exact weekday number match (0 for Sunday, 1 for Monday, etc.). If no exact match is found, check if a wildcard `REST_OF_DAYS` (enum value 7) entry is configured. If still not found, check for a `BUSINESS` (enum value 8) entry if the day is Monday-Friday.
2. **Lunch Exclusion**: Automatically split or adjust records to ensure no timesheet is generated during the `lunch_times` range.
3. **Descriptions**: Write all timesheet descriptions in the configured `preferred_description_lang`. Keep descriptions concise, informative, and free of filler/bloat words.

### 5. Updates, Deletion & Collision Overrides
When modifying existing timesheets, clearing logs, or overriding overlapping slots:
1. **Bulk Updates**: To modify details on existing timesheets, group them into a mapping dictionary and call the tool `update_timesheets` (takes `updates: Dict[int, TimesheetEditForm]`).
   - Check the returned `UpdateStats` object (successes in `updated`, failures in `error`/`errors`) to report operation status.
2. **Range Deletion**: Prefer `delete_timesheets_in_range` passing a `TimeRange` when clearing a full day or specific period.
3. **Individual Deletion**: Use `delete_timesheets` with a list of IDs for targeted removals.
4. **Display Stats**: Parse the returned `DeletionStats` object and print a summary reporting successfully deleted IDs and a clear description of any failures.

### 6. Exporting Timesheets & Sending Reports
Users frequently want a PDF of their logged hours and/or an email report sent to their boss or HR. These are two distinct steps — the PDF is produced locally, and the email is a separate text/HTML message. Reach for this whenever the user mentions exporting, downloading a PDF, "my hours for the week/month", or sending a report.

1. **Export the PDF**: Call `kimai_export_timesheet_pdf(daterange, filename)`.
   - `daterange` is a single string in the exact form `"YYYY-MM-DD - YYYY-MM-DD"` (note the spaces around the hyphen), e.g. `"2026-06-15 - 2026-06-21"`.
   - The tool logs in to the Kimai web portal, renders the PDF, and writes it to the storage folder. It returns the saved path — surface that path to the user so they know where the file landed.
   - Choose a descriptive `filename` reflecting the period (e.g. `"timesheet-2026-W25.pdf"` or `"timesheet-2026-06.pdf"`) so repeated exports don't overwrite each other.

2. **Send the report email**: Call `send_outlook_email(to_recipients, subject, body_content, body_type, cc_recipients)` using the recipients and CC defined in the profile's `report_config`.
   - **There is no attachment support.** The email cannot carry the PDF file. Instead, summarize the logged hours directly in `body_content` — total hours for the period and a short per-project/per-day breakdown drawn from the timesheets you listed. If the user needs the actual PDF, point them to the exported file path; don't claim it was attached.
   - Resolve recipients from `report_config`: use the `"weekly"` entry for weekly reports and `"monthly"` for monthly. Apply its `recipients`, `carbon_copy` (→ `cc_recipients`), `subject`, and `body` as the starting template, then enrich the body with the actual hours.
   - Default `body_type` to `"Text"`; use `"HTML"` only if you're formatting a table and the user wants it.
   - If `report_config` is missing the needed entry, fall back to interviewing the user (Section 1, Step 6) before sending.

3. **Pull the numbers before reporting**: To build an accurate summary, call the **`get_timesheet_summary`** tool with the target date range (e.g. `daterange="2026-08-01 - 2026-08-31"` or `start`/`end`). It returns pre-aggregated totals, billable hours, project breakdowns, and daily hours without needing to manually compute sums or run scripts. Alternatively, call `list_timesheets` to inspect individual entries. Never invent totals — report only what Kimai contains.


## Common Validation & API Pitfalls (CRITICAL)

To prevent validation errors and failing calls:
1. **MCP Server Identifier**: When invoking lazy tools via `call_mcp_tool`, always pass `ServerName: "KimAI"` (exact case with capital **AI**).
2. **Model Loading on Write Operations**: Before performing ANY write, update, save, or creation operation (including `save_user_profile`, `create_timesheets`, and `update_timesheets`), the agent **MUST** load and review the corresponding data structure and payload schemas from [references/MODELS.md](references/MODELS.md). Fill all payloads strictly aligning with the documented model types, constraints, and mandatory fields to eliminate validation errors.
3. **Profile Save Payload Structure**:
   * **Parameter Name**: When calling `save_user_profile`, you **MUST** pass the user profile data wrapped under the parameter key `"profile"`. Do NOT use `"profile_data"` or other root parameters.
   * **Full ISO 8601 DateTimes for Schedules**: The `duty_schedule` and `lunch_times` start and end times **MUST** be complete ISO 8601 UTC DateTime strings containing both date and time (e.g., `"2026-06-18T08:30:00Z"`). Do NOT pass simple times like `"08:30:00"`.
4. **Query Parameter Names (`start` / `end` vs `begin`)**:
   * Query tools (`list_timesheets`, `get_available_times_in_range`, `get_timesheet_summary`) use **`start`** and **`end`** for date filtering (though `list_timesheets` also accepts `begin` as an alias for resilience).
   * Write/creation models (`TimesheetEditForm`) use **`begin`** (or `start` which maps to alias `begin`).
5. **Timesheet Creation Tool**:
   * Always prefer calling `create_timesheets` (which takes a list of `TimesheetEditForm` objects containing `start`, `end`, `project`, `activity`, `description`, etc.) to create timesheets. Do NOT use `create_outlook_timesheet` as it is deprecated.
6. **Updating Timesheets**:
   * When calling `update_timesheets` or editing a timesheet entry, the `start` and `end` fields are **mandatory** in the request body even if they are not being changed.
7. **Business Schedule & Multi-Event Collisions**:
   * Prior to importing calendar meetings, check if there are existing entries in Kimai or overlapping schedules (e.g., two meetings at the same time). Resolve collisions locally (by warning the user or merging them) before submitting them to Kimai to prevent `400 Bad Request` responses.
8. **PDF Export Date Range Format**:
   * `kimai_export_timesheet_pdf` takes a single `daterange` string shaped exactly `"YYYY-MM-DD - YYYY-MM-DD"` (spaces around the hyphen), NOT two separate datetime parameters and NOT ISO timestamps. The tool returns the saved file path; report it to the user rather than implying the file was emailed or attached.
9. **Email Has No Attachments**:
   * `send_outlook_email` only accepts `to_recipients`, `subject`, `body_content`, `body_type`, and `cc_recipients`. It cannot attach the exported PDF. Put the hours summary in the body and reference the PDF's file path separately. Never tell the user a file was attached.
10. **Use `get_timesheet_summary` for Reporting**:
   * Always use `get_timesheet_summary` to compute monthly/weekly sums and project breakdowns instead of executing terminal/python scripts on the filesystem.

## Appendix: Data Models & Payloads Reference
For the detailed Pydantic models schema documentation, payload sanitization requirements, and User Profile JSON structures, always refer to [references/MODELS.md](references/MODELS.md). Ensure all profiles saved and write payloads sent conform exactly to the layouts specified in that document.

