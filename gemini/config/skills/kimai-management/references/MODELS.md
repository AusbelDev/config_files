# Kimai MCP Models Documentation

This file documents the key model structures used in Kimai automation, calendar synchronization, and user profiles. Refer to this document whenever you need to save/modify the user profile or build timesheet payloads.

---

## 1. User Profile Structure

Save or update the user profile at `file://kimai_user_profile.json` using the `save_user_profile` tool or by writing directly to `.mcp_context/kimai_user_profile.json`.

> **Fresh setup**: The profile's `current_projects` tree is auto-generated from the locally cached Kimai metadata (`kimai_customers.json`, `kimai_projects.json`, `kimai_activities.json`). Those caches only exist after `context_download` has run at least once. On a brand-new machine, call `context_download` **before** retrieving/initializing the profile — otherwise initialization has no metadata to map and will fail. See SKILL.md Section 1 "Fresh Setup".

```json
{
  "preferred_description_lang": "spanish", // string
  "duty_schedule": [ // List of TimeRange objects
    {
      "weekday": 1, // Weekday Enum: SUN=0, MON=1, TUE=2, WED=3, THU=4, FRI=5, SAT=6, REST_OF_DAYS=7, BUSINESS=8
      "start": "2026-06-18T08:30:00Z", // ISO string with UTC timezone info
      "end": "2026-06-18T17:30:00Z"
    }
  ],
  "lunch_times": [ // List of TimeRange objects
    {
      "weekday": 7, // REST_OF_DAYS (wildcard for days not explicitly defined)
      "start": "2026-06-18T14:00:00Z",
      "end": "2026-06-18T15:00:00Z"
    }
  ],
  "current_projects": {
    "CUSTOMER_ABBR": {
      "id": 4, // integer
      "name": "Customer Name",
      "abbr": "CUSTOMER_ABBR",
      "assigned_time": 1.0, // float
      "teammates": ["colleague@company.com"], // List of teammate email strings on Customer level
      "projects": {
        "PROJECT_ID": { // string key representing project ID
          "id": 404, // integer
          "name": "Project Name",
          "internal": false, // boolean
          "activities": [
            {
              "id": 936, // integer
              "name": "Activity Name"
            }
          ]
        }
      }
    }
  },
  "meetings_map": { // Dictionary mapping meeting subjects to project details
    "Meeting Subject": {
      "project_id": 404, // integer project ID
      "subject": "Meeting Subject" // string subject matching the key
    }
  },
  "user_prompts": [ // List of instructions strings
    "Prompt String"
  ],
  "enabled_scheduled": true, // boolean, default true. If false, skips task scheduling setup.
  "report_config": { // Dictionary mapping 'weekly'/'monthly' to report settings
    "weekly": {
      "recipients": ["boss@company.com"],
      "carbon_copy": [],
      "subject": "Weekly Kimai Hours Report",
      "body": "Hi Boss, here is my report of Kimai hours for this week."
    },
    "monthly": {
      "recipients": ["hr@company.com"],
      "carbon_copy": ["boss@company.com"],
      "subject": "Monthly Kimai Hours Report",
      "body": "Hi HR, here is my report of Kimai hours for this month."
    }
  },
  "scheduled_tasks": [ // List of ScheduledTask objects
    {
      "task": "send_weekly_report", // string action
      "frequency": "weekly", // string frequency
      "time": "17:00:00" // Time format (HH:MM:SS)
    }
  ],
  "updated_at": "2026-06-18T11:49:00" // ISO string
}
```

---

## 2. API Edit Form Models & Request Payloads

The Kimai API is strict regarding POST/PATCH request payloads. The following sections outline the JSON structures, example values, and validation warnings for each request model.

### A. TimesheetEditForm
Used for creating (`create_timesheets`) or editing (`update_timesheet` / `update_timesheets`) timesheet logs.

```json
{
  "begin": "2026-06-19T08:30:00Z", // Required. ISO 8601 string (maps to 'start')
  "end": "2026-06-19T17:30:00Z", // Optional. ISO 8601 string. Mandatory on update_timesheets!
  "project": 404, // Required. Integer Project ID (must exist in current_projects)
  "activity": 937, // Required. Integer Activity ID (must exist under the project)
  "description": "Coding Atrium implementation adjustments", // Optional string
  "tags": "development,atrium" // Optional comma-separated list of strings
}
```

> [!WARNING]
> **Mandatory Fields on Update**: When modifying a timesheet via `update_timesheets`, the `begin` (`start`) and `end` fields **MUST** be supplied in the payload, even if they are not being changed. Omitting them will cause validation failures.

---

### B. ActivityEditForm
Used for creating or managing activities (`create_activity`).

```json
{
  "name": "Customization", // Required string. 2-150 chars
  "comment": "External development tasks", // Optional string
  "invoiceText": "Customization fee details", // Optional string
  "project": 404, // Optional. Integer Project ID (omitted for global activities)
  "color": "#dd1d00", // Optional. HTML Hex format color string
  "visible": true, // Optional boolean. Defaults to true
  "billable": true // Optional boolean. Defaults to true
}
```

---

### C. ProjectEditForm
Used for creating or managing project entities.

```json
{
  "name": "Atrium Implementation JOC/JTA", // Required string. 2-150 chars
  "comment": "Main deployment project", // Optional string
  "invoiceText": "Aeromexico project scope details", // Optional string
  "orderNumber": "PO-12345", // Optional string
  "orderDate": "2026-06-18T00:00:00Z", // Optional ISO 8601 string
  "start": "2026-06-18T08:30:00Z", // Optional ISO 8601 string
  "end": "2026-07-18T17:30:00Z", // Optional ISO 8601 string
  "customer": 4, // Required. Integer Customer ID
  "color": "#00ff00", // Optional. HTML Hex format color string
  "visible": true, // Optional boolean
  "billable": true, // Optional boolean
  "globalActivities": false // Optional boolean (alias: globalActivities)
}
```

---

### D. CustomerEditForm
Used for creating or managing customer entities.

```json
{
  "name": "AEROMEXICO", // Required string
  "number": "AMX-1", // Optional string
  "comment": "Main commercial aviation client", // Optional string
  "company": "Aeromexico S.A. de C.V.", // Optional string
  "vatId": "MX12345678", // Optional string (alias: vatId)
  "contact": "John Doe", // Optional string
  "address": "Terminal 2 AICM, Mexico City", // Optional string
  "country": "MX", // Required. ISO 2-letter country code (e.g., 'MX', 'US')
  "currency": "MXN", // Required. 3-letter currency code (e.g., 'MXN', 'USD')
  "phone": "+525512345678", // Optional string
  "fax": null, // Optional string
  "mobile": null, // Optional string
  "email": "contact@company.com", // Optional string
  "homepage": "https://company.com", // Optional string
  "timezone": "America/Mexico_City", // Required. Valid IANA timezone string
  "color": "#ffffff", // Optional HTML Hex format color string
  "visible": true, // Optional boolean
  "billable": true // Optional boolean
}
```

---

### E. Export & Email Payloads

**`kimai_export_timesheet_pdf`** — renders the user's timesheets to a PDF on disk.

```json
{
  "daterange": "2026-06-15 - 2026-06-21", // Required. Single string, exact form "YYYY-MM-DD - YYYY-MM-DD" with spaces around the hyphen. NOT two params, NOT ISO timestamps.
  "filename": "timesheet-2026-W25.pdf"    // Optional. Defaults to "timesheet.pdf". Use a period-specific name to avoid overwrites.
}
```
> Returns the saved file path string. The PDF is written to the storage folder — surface this path to the user.

**`send_outlook_email`** — sends a plain email via Microsoft Graph. **No attachment support.**

```json
{
  "to_recipients": ["boss@company.com"],   // Required. List of recipient addresses.
  "subject": "Weekly Kimai Hours Report",  // Required string.
  "body_content": "Hi Boss, total 40h ...", // Required string. Put the hours summary HERE — the PDF cannot be attached.
  "body_type": "Text",                      // Optional. "Text" (default) or "HTML".
  "cc_recipients": ["pm@company.com"]       // Optional. List of CC addresses (maps from report_config.carbon_copy).
}
```
> [!WARNING]
> This tool **cannot** attach files. To deliver hours, summarize them in `body_content`; reference the exported PDF by its file path if the user needs the document itself.

---

### F. Timesheet Query & Summary Models

**`list_timesheets`** — fetches timesheets with query filters.
```json
{
  "start": "2026-08-01T00:00:00Z", // Optional ISO 8601 string. ('begin' is also accepted as alias)
  "end": "2026-08-31T23:59:59Z",   // Optional ISO 8601 string
  "projects": "125,404",            // Optional comma-separated string of project IDs
  "activities": "1955,908",         // Optional comma-separated string of activity IDs
  "user": "109",                    // Optional string user ID or "all"
  "size": 500,                      // Optional integer (default 20)
  "page": 1,                        // Optional integer (default 1)
  "billable": true                  // Optional boolean
}
```

**`get_timesheet_summary`** — aggregates total hours, project breakdowns, daily totals, and billable vs non-billable stats.
```json
{
  "daterange": "2026-08-01 - 2026-08-31", // Optional string "YYYY-MM-DD - YYYY-MM-DD"
  "start": "2026-08-01T00:00:00Z",        // Optional ISO 8601 string (used if daterange omitted)
  "end": "2026-08-31T23:59:59Z",          // Optional ISO 8601 string
  "projects": "125,404"                   // Optional comma-separated string of project IDs
}
```
> Returns a structured summary containing `total_hours`, `billable_hours`, `non_billable_hours`, `by_project`, `by_day`, and `timesheets_count`. Use this tool directly for email reports instead of executing manual bash/python calculation scripts.

---

### G. ScheduledTask

Entries in the profile's `scheduled_tasks` list (see Section 1), used when `enabled_scheduled` is true.

```json
{
  "task": "send_weekly_report", // string action identifier (e.g. "send_weekly_report", "send_monthly_report", "export_pdf")
  "frequency": "weekly",        // string: "weekly" or "monthly"
  "time": "17:00:00"            // Time string (HH:MM:SS); for monthly, pair with the configured day-of-month in user_prompts/other_instructions
}
```

---

## 3. Critical Validation Rules & Warnings

- **MCP Server Name**: When calling lazy MCP tools via `call_mcp_tool`, the server name is strictly **`"KimAI"`** (note uppercase **AI**).
- **Datetime Format**: All dates sent to the API must be complete ISO 8601 strings (e.g., `"2026-06-18T08:30:00Z"`). Simply providing time strings like `"08:30"` will result in parsing failures.
- **Mandatory Fields**: Ensure that any payload keys marked **Required** above are supplied. Never send `null` or omit keys that the Pydantic schemas require.
- **Preserve User Profiles**: When saving a profile with `save_user_profile`, **always** match the root key format: `{"profile": <UserProfileData>}`. Do not omit the `abbr` field under projects or customers, as the backend validates its presence strictly.
- **Forced Context Refresh**: To force re-download of timesheet metadata from the server after making updates or on the same calendar day, pass `update_now: true` to `context_download`.


