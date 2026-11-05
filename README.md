# Everyday

A calm iPhone app for your day: tasks, reminders, lists, your calendar, your gym routine and
the books, shows and restaurants you want to get to, all in one place.
Built with SwiftUI and SwiftData.

<p align="center">
  <img src="docs/screenshots/today.png" width="250" alt="Today screen">
  &nbsp;
  <img src="docs/screenshots/today-dark.png" width="250" alt="Today screen in dark mode">
</p>

## Features

### Today
See what's coming up on your calendar and what's on your list for today. Below that are your
next workout and **Up next**: the book you're reading and the show you're watching (tap one
to open it). Tap **+** to add a task, a reminder or a calendar event.

<p align="center">
  <img src="docs/screenshots/add-menu.png" width="250" alt="Add menu with task, reminder and event">
</p>

### Calendar
A week view with your events from Google, Outlook and iCloud alongside your tasks.
Events are colored by Work and Personal. You can create, edit and delete events, choose which
calendar they go in, and set an alert. Pull down to fetch the latest changes.

<p align="center">
  <img src="docs/screenshots/calendar.png" width="250" alt="Calendar screen">
</p>

### Tasks and reminders
Tasks are grouped into Overdue, Today, Upcoming, Someday and Done. Give a task a time, a
place, a note and an icon. Reminders send a notification at the time you choose, and
repeating tasks (every day, weekday, week or month) move to their next date when you check
them off. Turn on **Add to calendar** to put a task on your real calendar.

<p align="center">
  <img src="docs/screenshots/tasks.png" width="250" alt="Tasks screen">
  &nbsp;
  <img src="docs/screenshots/task-detail.png" width="250" alt="Task detail screen">
  &nbsp;
  <img src="docs/screenshots/new-reminder.png" width="250" alt="New reminder screen">
</p>

### Lists
Keep lists for anything: groceries, weekend chores, books to read. Grocery items can have a
quantity and a section (like Produce), and checked items move to "In the basket". Lists can
be renamed and given their own icon and color.

<p align="center">
  <img src="docs/screenshots/lists.png" width="250" alt="Lists screen">
</p>

### Library
Save books you want to read, TV shows you want to watch and restaurants you want to try.
Books and shows move from **Want to read** to **Reading** to **Finished** (or the watching
versions) with a single tap; restaurants go from **Want to try** to **Been there**. Give each a
genre or cuisine, filter by it, and rate what you've finished with 1–5 stars. Tap a section's
heading to fold it away.

Start typing a title and pick a match to fill in the details for you: the author or network,
the genre and a cover. Books come from [Open Library](https://openlibrary.org), shows from
[TVmaze](https://www.tvmaze.com) and restaurants from Apple Maps, so no account is needed.
Long-press a restaurant and choose **Plan a visit** to put it on your calendar.

<p align="center">
  <img src="docs/screenshots/library-lookup.png" width="250" alt="Adding a book with matches and covers">
</p>

### Gym
Keep your workout routine in the app. Copy it from the Notes app and tap **Paste from Notes**;
each day (like "Leg x Glutes Day") becomes a workout, and the days take turns in order. At the
gym, tick off each exercise as you go. When you tap **Finish workout**, the app offers to raise
each weight by 5 or 10 lbs for next time. Tap an exercise to change it or to see the weights
you've used over time. Find it on Today or at the top of the **Lists** tab.

<p align="center">
  <img src="docs/screenshots/gym.png" width="250" alt="Gym screen with workout days">
  &nbsp;
  <img src="docs/screenshots/workout.png" width="250" alt="A workout with exercises ticked off">
</p>

### Search
The magnifying glass at the top of each tab searches everything at once: tasks, list items,
lists, books, shows, restaurants and calendar events.

### Home screen widget
Add the **Today** widget to see your next events and today's tasks without opening the app.
It comes in small, medium and large sizes. To add it, long-press your home screen, tap
**Edit → Add Widget** and choose **Everyday**.

### Light and dark mode
Follows your iPhone's setting, or pick Light or Dark yourself by tapping your profile picture
(or initials) on the Today screen. That's also where you set your name and photo. The app icon has light, dark and tinted versions.

## Running the app

1. Open `EverydayApp.xcodeproj` in Xcode.
2. Choose an iPhone simulator or your own iPhone, then press **Run** (⌘R).
3. To see the app filled in, go to the **Lists** tab and tap **Load sample data**.

The app asks for two permissions:

- **Calendar:** to show, add and edit your events. Your Google or Outlook calendars appear once
  those accounts are added in iPhone **Settings → Apps → Calendar → Calendar Accounts**.
- **Notifications:** to send task reminders.

## Project layout

| File | What it does |
| --- | --- |
| `EverydayApp.swift` | App entry point; sets up storage, the calendar connection and Light/Dark mode |
| `ContentView.swift` | The five tabs, plus keeping reminders and calendars up to date |
| `TodayView.swift`, `CalendarView.swift`, `ListsView.swift`, `LibraryView.swift`, `TasksView.swift` | The five main screens |
| `GymView.swift`, `Gym.swift` | The Gym screens, plus workouts, exercises, weight history and reading a routine pasted from Notes |
| `LibraryLookup.swift` | Looks up books, shows and restaurants as you type, and loads covers |
| `Search.swift` | Searching everything from the magnifying glass |
| `WidgetSync.swift` | Shares today's events and tasks with the home screen widget |
| `EverydayWidget/` | The home screen widget (a separate part of the app that iOS runs on its own) |
| `TaskDetailView.swift`, `ListDetailView.swift` | Screens for a single task or list |
| `Sheets.swift`, `EventEditSheet.swift`, `CalendarSettingsSheet.swift` | Pop-up screens for adding and editing |
| `Models.swift` | Tasks, lists, and Library books, shows and restaurants, including the repeat logic |
| `CalendarStore.swift` | Reads and writes calendar events through Apple's EventKit |
| `Reminders.swift` | Schedules task notifications |
| `Components.swift`, `EventCard.swift` | Reusable pieces like checkboxes, rows and cards |
| `Profile.swift` | Your profile picture: saving it and drawing the round avatar |
| `Theme.swift` | Colors (light and dark), date formatting and appearance settings |
| `SampleData.swift` | The demo data behind **Load sample data** |
