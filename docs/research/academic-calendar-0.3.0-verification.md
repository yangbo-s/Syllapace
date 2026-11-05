# Academic calendar input verification — 0.3.0

Verified on 2026-11-04. These checks used public university documents and synthetic fixtures; no user credentials, private course data, or model requests were involved.

## Public sources

- [CMU official calendar directory](https://www.cmu.edu/hub/calendar/) lists the annual PDF, iCalendar subscription and Pittsburgh class-meeting workbook. It explicitly distinguishes doctoral, Heinz, Tepper, Qatar and Africa calendars.
- [Official iCalendar feed](https://events.cmu.edu/live/ical/events/group/Academic%20Calendar/header/Academic%20Calendar%20Events): downloaded 99,686 bytes. The compiled `SyllapaceKit.ICalendarReader` read **107 VEVENT records into 107 events, with 0 warnings**. Every event had an empty `courseID` and the independent school-calendar scope.
- Observed feed DTSTART coverage was **2026-11-09 00:00 America/New_York through 2027-08-10 00:00 America/New_York**. This is a rolling feed and does not establish complete Fall 2026 coverage.
- [2026–2027 academic calendar PDF](https://www.cmu.edu/hub/calendar/docs/2627-academic-calendar.pdf): official annual-document preset, routed through the ordinary document import and review workflow.
- [2026–2027 Pittsburgh class-meeting workbook](https://www.cmu.edu/hub/calendar/docs/2627-pgh-class-meeting-days.xlsx): downloaded 26,213 bytes. The compiled `SpreadsheetReader` produced **9,874 UTF-8 text bytes, 1 worksheet and 105 rows**. Cell addresses, semester columns, numeric dates and Y/No teaching-day values were retained. Workbook dates such as 2026-08-24 and 2027-01-18 were decoded as calendar dates instead of Excel serials.

The public-source probe only printed counts, date bounds and a short public header sample. No downloaded source payload or probe binary is included in the repository or release.

## Automated validation

`./tools/test.sh` completed successfully with exit code 0 with test-runner timestamp `2026-11-04 20:40:19`. The test runner reported:

```text
Build complete! (3.09 sec)
Test run with 167 tests in 19 suites passed after 0.516 seconds.
```

This run covered calendar time zones, exclusive all-day end dates, bounded recurrence expansion, COUNT/UNTIL/BYDAY/BYMONTH, exceptions and moved occurrences, cancellation/unsupported-series review transitions, UID stability, safe redirects, duration overflow, task cancellation and expanded payload limits. XLSX tests covered 1900/1904 date systems, shared and inline text, cached formula values, midnight carry, DTD/external-relationship rejection, cell/XML limits, repeated shared-string expansion and an actual temporary ZIP archive. The indexed reconciliation tests included 20,000 repeated occurrences and 5,000 changed approved dates.

The first full test stdout was not redirected to a file; the tool retained the exit status and summary but truncated the long displayed output. This document is a verification summary, **not a complete raw test log**. The release owner should retain the final full release-check log.

A subsequent review added one guard and regression case for a single nonrecurring event whose EXDATE names an unrelated date. That final small change requires the release owner's next test run (expected total: 168 tests).

## Protocol and format references

- [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545): date values, exclusive DTEND, recurrence rules and overrides.
- [Microsoft: retrieve cell values](https://learn.microsoft.com/en-us/office/open-xml/spreadsheet/how-to-retrieve-the-values-of-cells-in-a-spreadsheet): shared-string and typed-cell representation.
- [Microsoft: Excel date systems](https://support.microsoft.com/en-us/excel/date-systems-in-excel): 1900/1904 serial-date conversion.
- [Microsoft: fictitious 1900 leap day](https://learn.microsoft.com/en-us/office/troubleshoot/excel/wrongly-assumes-1900-is-leap-year): serial 60 is explicitly preserved as an invalid date instead of inventing February 29, 1900.
