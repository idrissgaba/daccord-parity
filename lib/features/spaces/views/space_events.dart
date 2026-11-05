import 'package:bonfire/theme/app_icons.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/voice/utils/stage_logic.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/spaces/controllers/space_events.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/event_logic.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bonfire/shared/components/context_menu.dart';

part 'space_events/event_editor.dart';

/// Whether the signed-in member may plan events in [spaceId].
bool _canManageEvents(WidgetRef ref, String spaceId) {
  final space = ref.watch(
    spacesControllerProvider.select(
      (spaces) => spaces?.firstWhereOrNull((s) => s.id == spaceId),
    ),
  );
  return accordHasPermission(
    ref.watchAccordPermissions(space, spaceId),
    AccordPermission.manageEvents,
  );
}

String _cdn(String? cdnUrl, String path) =>
    AccordCDN.resolvePath(path, cdnUrl: cdnUrl ?? '');

/// The "Events" row at the top of a space's channel list: a red LIVE line
/// while an event is under way, otherwise how many are coming up.
class SpaceEventsEntry extends ConsumerWidget {
  const SpaceEventsEntry({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverKey = ref.watchActiveServerKey() ?? '';
    final events =
        ref.watch(spaceEventsControllerProvider(serverKey, spaceId)) ??
        const <AccordScheduledEvent>[];
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final live = events.where((e) => e.isActive).firstOrNull;
    final label = live != null
        ? 'LIVE · ${live.name}'
        : events.isEmpty
        ? 'Events'
        : events.length == 1
        ? '1 Event'
        : '${events.length} Events';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 13, 8, 1),
          child: Material(
            color: live != null
                ? colors.red.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: const Key('space-events-entry'),
              // The dialog it opens would hand focus back here and leave the
              // row lit up as if still selected.
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(8),
              hoverColor: colors.hover,
              onTap: () => showSpaceEvents(context, spaceId: spaceId),
              child: SizedBox(
                height: 32,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(
                        live != null ? AppIcons.podcasts : AppIcons.event,
                        size: 20,
                        color: live != null ? colors.red : colors.gray,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            fontSize: 16,
                            fontWeight: live != null
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: live != null ? colors.red : colors.gray,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // The hairline that separates the space rows from the channels.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Divider(height: 1, thickness: 1, color: colors.hairline),
        ),
      ],
    );
  }
}

/// Opens the space's events: what's coming up, who's interested, and (for
/// members who manage events) planning, starting, ending and cancelling.
Future<void> showSpaceEvents(BuildContext context, {required String spaceId}) {
  return showDialog<void>(
    context: context,
    builder: (_) => SpaceEventsDialog(spaceId: spaceId),
  );
}

class SpaceEventsDialog extends ConsumerWidget {
  const SpaceEventsDialog({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final events = ref.watch(spaceEventsControllerProvider(serverKey, spaceId));
    final canManage = _canManageEvents(ref, spaceId);
    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 560, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(AppIcons.event, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Text('Events', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (canManage)
                    FilledButton.icon(
                      key: const Key('event-create'),
                      onPressed: () =>
                          showEventEditor(context, spaceId: spaceId),
                      icon: const Icon(AppIcons.add, size: 18),
                      label: const Text('Create event'),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(AppIcons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: events == null
                    ? const LoadingView()
                    : events.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          canManage
                              ? 'No events yet. Plan one for everyone!'
                              : 'No events coming up.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: events.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) => EventCard(
                          event: events[index],
                          canManage: canManage,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One event: cover, when, name, description, where, how many are
/// interested, and its actions.
class EventCard extends ConsumerStatefulWidget {
  const EventCard({super.key, required this.event, required this.canManage});

  final AccordScheduledEvent event;
  final bool canManage;

  @override
  ConsumerState<EventCard> createState() => _EventCardState();
}

class _EventCardState extends ConsumerState<EventCard> {
  bool _busy = false;

  AccordScheduledEvent get _event => widget.event;

  String get _serverKey => ref.readActiveServerKey() ?? '';

  /// Runs [action] and applies the event it answers with.
  Future<void> _run(
    Future<RestResult> Function(AccordClient client) action,
    String failure,
  ) async {
    final client = ref.accordClient;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await action(client);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      showInfoSnack(context, result.errorMessageOr(failure));
      return;
    }
    final controller = ref.read(
      spaceEventsControllerProvider(_serverKey, _event.spaceId).notifier,
    );
    final data = result.data;
    if (data is AccordScheduledEvent) {
      if (eventIsOpen(data)) {
        controller.upsert(data);
      } else {
        controller.remove(data.id);
      }
    } else {
      controller.remove(_event.id);
    }
  }

  void _setStatus(String status, String failure) => _run(
    (client) =>
        client.events.update(_event.spaceId, _event.id, {'status': status}),
    failure,
  );

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${_event.name}?',
      message: 'It disappears for everyone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok != true || !mounted) return;
    await _run(
      (client) => client.events.delete(_event.spaceId, _event.id),
      'Could not delete the event',
    );
  }

  Future<void> _addToCalendar(String where) async {
    final ics = buildIcs(_event, where: where, now: DateTime.now());
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: 'Add to calendar',
        fileName: icsFileName(_event),
        type: FileType.custom,
        allowedExtensions: const ['ics'],
        bytes: Uint8List.fromList(utf8.encode(ics)),
      );
    } catch (_) {
      if (mounted) showInfoSnack(context, 'Could not save the calendar file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final event = _event;
    final channels =
        ref.watch(
          accordChannelsControllerProvider(_serverKey, event.spaceId),
        ) ??
        const <AccordChannel>[];
    final channel = channels.firstWhereOrNull((c) => c.id == event.channelId);
    final where = event.isVoice
        ? (channel == null ? 'Voice channel' : '🔊 ${channel.name}')
        : (event.location ?? '');
    final cdnUrl = ref.watchCdnUrl();
    final interested = event.interested ?? false;
    final inVoiceHere = ref.watch(
      voiceControllerProvider.select((v) => v.channelId == event.channelId),
    );

    return Container(
      key: ValueKey('event-${event.id}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.darkGray,
        borderRadius: BorderRadius.circular(8),
        border: event.isActive ? Border.all(color: colors.red) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (event.image != null)
            CachedNetworkImage(
              imageUrl: _cdn(cdnUrl, event.image!),
              height: 120,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventWhenLabel(event, DateTime.now()),
                  style: theme.textTheme.labelMedium!.copyWith(
                    color: event.isActive ? colors.red : colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(event.name, style: theme.textTheme.titleMedium),
                if (event.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    event.description!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      event.isVoice
                          ? AppIcons.volumeUp
                          : AppIcons.placeOutlined,
                      size: 16,
                      color: colors.gray,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        where,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: colors.gray,
                        ),
                      ),
                    ),
                    Icon(AppIcons.peopleOutline, size: 16, color: colors.gray),
                    const SizedBox(width: 4),
                    Text(
                      '${event.userCount} interested',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.gray,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (event.isActive &&
                        event.isVoice &&
                        event.channelId != null &&
                        !inVoiceHere)
                      FilledButton.icon(
                        key: ValueKey('event-join-${event.id}'),
                        onPressed: () => ref
                            .read(voiceControllerProvider.notifier)
                            .join(event.channelId!, event.spaceId),
                        icon: const Icon(AppIcons.call, size: 16),
                        label: const Text('Join'),
                      ),
                    OutlinedButton.icon(
                      key: ValueKey('event-interested-${event.id}'),
                      onPressed: _busy
                          ? null
                          : () => _run(
                              (client) => client.events.setInterested(
                                event.spaceId,
                                event.id,
                                !interested,
                              ),
                              'Could not update your interest',
                            ),
                      icon: Icon(
                        interested
                            ? AppIcons.check
                            : AppIcons.notificationsNone,
                        size: 16,
                      ),
                      label: Text(interested ? 'Interested' : 'Interested?'),
                    ),
                    IconButton(
                      tooltip: 'Add to calendar',
                      onPressed: () => _addToCalendar(where),
                      icon: const Icon(AppIcons.eventAvailable, size: 18),
                    ),
                    if (widget.canManage)
                      AccordMenuButton(
                        key: ValueKey('event-menu-${event.id}'),
                        tooltip: 'Manage event',
                        entries: () => _busy
                            ? const []
                            : [
                                if (!event.isActive)
                                  AccordMenuEntry(
                                    label: 'Start Now',
                                    onSelected: () => _setStatus(
                                      'active',
                                      'Could not start the event',
                                    ),
                                  ),
                                if (event.isActive)
                                  AccordMenuEntry(
                                    label: 'End Event',
                                    onSelected: () => _setStatus(
                                      'completed',
                                      'Could not end the event',
                                    ),
                                  ),
                                AccordMenuEntry(
                                  label: 'Edit',
                                  onSelected: () => showEventEditor(
                                    context,
                                    spaceId: event.spaceId,
                                    existing: event,
                                  ),
                                ),
                                if (!event.isActive)
                                  AccordMenuEntry(
                                    label: 'Cancel Event',
                                    onSelected: () => _setStatus(
                                      'canceled',
                                      'Could not cancel the event',
                                    ),
                                  ),
                                const AccordMenuEntry.divider(),
                                AccordMenuEntry(
                                  label: 'Delete',
                                  destructive: true,
                                  onSelected: _delete,
                                ),
                              ],
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(AppIcons.moreVert, size: 20),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Plans a new event in [spaceId], or edits [existing].
Future<void> showEventEditor(
  BuildContext context, {
  required String spaceId,
  AccordScheduledEvent? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => EventEditorDialog(spaceId: spaceId, existing: existing),
  );
}
