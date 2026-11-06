---
title: Managing Your Space
description: Configure channels, roles, and settings for your space.
order: 1
section: administration
---

# Managing Your Space

If you have admin permissions, you can manage your space's channels, roles, and settings.

## Accessing Server Settings

Right-click a space icon in the space bar (or click the space name above the
channel list) and choose **Server Settings**, or one of its pages from the
**Server Settings ›** submenu. The settings fill the window: the pages you may
open are listed at the left, and the round **✕** (or **Escape**) closes them.

| Group | Pages |
|---|---|
| — | Server Profile, Engagement |
| Expression | Emoji, Stickers, Soundboard |
| People | Members, Roles, Invites, Access |
| Apps | Integrations, Arcade |
| Moderation | Audit Log, Bans, AutoMod, Reports |
| — | Transfer Ownership, Delete Server (owner only) |

Server Profile, Engagement and Access, as well as the role editor and a
channel's Overview, keep your edits until you choose **Save Changes** in the
"Careful – you have unsaved changes!" bar at the bottom; **Reset** undoes them.
While edits are pending you cannot switch pages or close the settings — the bar
flashes red instead.

## Server Profile

Change the name, icon, banner and description. The card at the right previews
how the server looks in invites. Icons are exported as PNG up to 512 pixels;
banners use a 16:9 crop up to 1024 pixels wide. The crops show in the preview
immediately and are sent with **Save Changes**. Saved replacements refresh the
settings preview and space bar during the same session, even when the server
reuses the image URL.

## Engagement and Access

**Engagement** sets the system messages channel, the default notification
level for new members, and opens the [welcome screen](#welcome-screen) editor.
**Access** chooses whether people join by invite only or can find the server in
Server Discovery, whether it is age-restricted, the rules channel, guest access,
the verification level and the explicit media filter.

## Emoji and Stickers

Members with **Create Expressions** can upload emoji, stickers and sounds, and
rename or delete their own; **Manage Expressions** manages everyone's.

## Members

**Members** lists everyone with when they joined and their roles; click a row
(or its **…**) for the member menu — profile, roles, timeout, kick, ban.

## Channels

### Creating a Channel

Use **Create Channel** from the space name's menu or a category's **+**, pick a
type, a name and, for leaf channels, a topic.

### Editing a Channel

Hover a channel and click its gear (or right-click it and choose **Edit
Channel**). Channel settings fill the window too: **Overview** (name, topic with
its formatting toolbar, slowmode, content visibility, type), **Permissions**,
**Invites** and **Integrations** for that channel, and **Delete Channel**.

### Categories

Channels can be organized into categories; a category's settings have
Overview, Permissions and Delete Category.

## Roles

Roles control what members can do in your space. **Roles** lists them with how
many members have each, under **Default permissions** (`@everyone`).

### Creating and editing a role

1. Click **Create Role** (or a role's row).
2. **Display**: set its name and colour, whether its members show separately,
   and whether anyone can mention it.
3. **Permissions**: switch each permission on or off (search the list, or
   **Clear permissions**).
4. **Manage Members**: add members to the role or remove them.
5. Choose **Save Changes**.

The role column beside the editor lets you switch roles and drag them to
reorder; the **…** menu views the server as that role or deletes it.
`@everyone` only has Permissions.

### Channel Permissions

You can set per-channel permission overrides for specific roles:

1. Open the channel's settings.
2. Go to **Permissions** and open **Advanced permissions**.
3. Add a role and set permissions to **Allow**, **Inherit**, or **Deny** for each permission.

## Welcome Screen

Open **Welcome Screen** from Server Settings › Engagement (needs Manage Space) to greet members
the first time they open the space. Write a short description and recommend up
to five channels, each with an emoji and a reason to go there. Turn on **Show
to new members** to enable it. Each member sees it once; tapping a recommended
channel opens it.

## Invites

See [Invites](invites.md) for details on inviting people to your server.

## Arcade

Open **Arcade** in Server Settings to enable reviewed games and manage the
space's Arcade. See [Managing Arcade](managing-arcade.md) for channel placement,
notifications, idle cleanup, and custom extensions.

## Webhooks

A webhook lets another service post into a text channel — monitoring alerts,
download notifications, build results. In **Server Settings → Integrations**
(you need the Manage Webhooks permission; a channel's own Integrations page
shows only its webhooks):

1. Click **Create Webhook** and pick the channel it posts in.
2. Click the link icon to copy its URL, and paste it into the service's
   notification settings (services that support chat webhooks accept it as is).
3. From the **⋮** menu you can rename it, move it to another channel, change its
   avatar, or delete it.

Keep the URL secret: anyone who has it can post in that channel. Deleting the
webhook stops the URL working; what it already posted stays. Messages from a
webhook (or a bot) show an **APP** badge next to the name. A webhook can't
notify `@everyone` unless the service explicitly asks to.

## Events

Plan things for the space — a movie night in a voice channel, a meetup
somewhere else. The **Events** row at the top of the channel list shows how
many are coming up, and turns red with **LIVE** while one is under way.

- **Create event** (needs the Manage Events permission): pick a voice channel or
  type a location, a name, a description, when it starts and (required for an
  event somewhere else) when it ends, and optionally a cover image.
- Anyone can click **Interested** — on the desktop app you get a notification
  when it starts. **Add to calendar** saves a `.ics` file for your calendar app.
- Events start on their own at their start time and end at their end time (or
  12 hours later if they have none). Managers can also **Start now**, **End
  event**, **Edit**, **Cancel event** or **Delete** from the event's menu.
- While a voice event is live, **Join** puts you in its channel.
