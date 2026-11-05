part of 'accord_home.dart';

/// Tint of a folder with no colour of its own.
Color _folderColor(SpaceFolder folder, BonfireThemeExtension colors) =>
    folder.color == null ? colors.primary : Color(folder.color!);

/// A collapsible folder tile in the rail. Tap toggles collapse; the management
/// menu opens on long-press (touch) or right-click (desktop); dragging reorders
/// the folder. It accepts dropped spaces (to add them) and dropped folders (to
/// reorder before it).
///
/// Closed, it is a tinted rounded square holding up to four member icons;
/// open, the folder glyph sits above its members inside a tinted drawer, as in
/// other chat apps.
class _FolderTile extends ConsumerStatefulWidget {
  const _FolderTile({
    required this.folder,
    required this.spaces,
    required this.connOf,
    required this.selectedSpaceId,
    required this.onSelect,
    required this.onDropSpace,
    required this.onReorderFolderBefore,
    required this.onMemberDropBefore,
  });

  final SpaceFolder folder;
  final List<_RailSpace> spaces;

  /// Per-space connection lookup so folder members can span servers: each
  /// member resolves its own CDN, owning server, and active state.
  final Map<String, _SpaceConn> connOf;
  final String? selectedSpaceId;
  final void Function(String serverKey, String spaceId) onSelect;

  /// A space [spaceId] was dropped on the folder tile: add it to this folder.
  final ValueChanged<String> onDropSpace;

  /// A folder [folderId] was dropped on this folder tile: move that folder
  /// before this one.
  final ValueChanged<String> onReorderFolderBefore;

  /// A space [draggedSpaceId] was dropped on member [targetMemberId]: place it
  /// in this folder before that member (reorder within, or move in positioned).
  final void Function(String draggedSpaceId, String targetMemberId)
  onMemberDropBefore;

  @override
  ConsumerState<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends ConsumerState<_FolderTile> {
  SpaceFolder get folder => widget.folder;
  List<_RailSpace> get spaces => widget.spaces;

  bool _isSelected(_RailSpace member) =>
      (widget.connOf[member.key]?.active ?? false) &&
      member.space.id == widget.selectedSpaceId;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final ctl = ref.read(settingsControllerProvider.notifier);
    final folderIcon = SpaceFolderIcon(
      folder: folder,
      spaces: {for (final member in spaces) member.key: member.space},
      cdnUrls: {
        for (final entry in widget.connOf.entries)
          entry.key: entry.value.cdnUrl,
      },
    );
    // Closed, the folder carries its members' unread pill and mention count;
    // open, each member shows its own.
    var unread = false;
    var mentions = 0;
    var selected = false;
    for (final member in spaces) {
      final badges = _watchSpaceBadges(
        ref,
        widget.connOf[member.key]?.serverKey ?? '',
        member.space.id,
      );
      unread = unread || badges.unread;
      mentions += badges.mentions;
      selected = selected || _isSelected(member);
    }

    final header = DragTarget<_RailDrag>(
      onWillAcceptWithDetails: (d) => switch (d.data) {
        _SpaceDrag(:final spaceId) => !folder.spaceIds.contains(spaceId),
        _FolderDrag(:final folderId) => folderId != folder.id,
      },
      onAcceptWithDetails: (d) {
        switch (d.data) {
          case _SpaceDrag(:final spaceId):
            widget.onDropSpace(spaceId);
          case _FolderDrag(:final folderId):
            widget.onReorderFolderBefore(folderId);
        }
      },
      builder: (context, candidate, _) {
        final highlight = candidate.isNotEmpty;
        return RailDraggable<_RailDrag>(
          data: _FolderDrag(folder.id),
          tooltip: folder.name.isEmpty ? 'Folder' : folder.name,
          feedback: Material(color: Colors.transparent, child: folderIcon),
          childWhenDragging: Opacity(opacity: 0.3, child: folderIcon),
          onMenu: (pos) => _folderMenu(context, ref, pos),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_kRailActiveRadius),
              border: highlight
                  ? Border.all(color: colors.primary, width: 2)
                  : null,
            ),
            child: _RailTile(
              // Only the closed folder stands in for its members.
              selected: folder.collapsed && selected,
              unread: folder.collapsed && unread,
              mentions: folder.collapsed ? mentions : 0,
              onTap: () => ctl.setFolderCollapsed(folder.id, !folder.collapsed),
              alwaysSquare: true,
              activeColor: _folderColor(folder, colors).withValues(alpha: 0.4),
              restColor: _folderColor(folder, colors).withValues(alpha: 0.4),
              builder: (_) => folderIcon,
            ),
          ),
        );
      },
    );

    if (folder.collapsed) return Center(child: header);

    // Open: a drawer 4 px wider than the tiles on each side, tinted, holding
    // the folder glyph and its members.
    return Center(
      child: Container(
        width: _kRailTileSize + 8,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.hover,
          borderRadius: BorderRadius.circular(_kRailTileSize / 2 + 4),
        ),
        child: Column(
          children: [
            header,
            for (final railSpace in spaces)
              Padding(
                padding: const EdgeInsets.only(top: _kRailGap),
                child: _FolderMemberTile(
                  space: railSpace.space,
                  entityKey: railSpace.key,
                  conn: widget.connOf[railSpace.key],
                  selected: _isSelected(railSpace),
                  onTap: () => widget.onSelect(
                    widget.connOf[railSpace.key]?.serverKey ?? '',
                    railSpace.space.id,
                  ),
                  onDropBefore: (draggedId) =>
                      widget.onMemberDropBefore(draggedId, railSpace.key),
                  onMenu: (pos) =>
                      _memberMenu(context, ref, ctl, railSpace, pos),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Context menu for a folder member (long-press on touch / right-click on
  /// desktop): the space icon menu, whose Move to… holds "Remove from
  /// Folder". [position] anchors it on desktop; null presents the touch sheet.
  Future<void> _memberMenu(
    BuildContext context,
    WidgetRef ref,
    SettingsController ctl,
    _RailSpace railSpace,
    Offset? position,
  ) {
    final space = railSpace.space;
    final serverKey = widget.connOf[railSpace.key]?.serverKey ?? '';
    return showAccordContextMenu(
      context,
      entries: _spaceIconMenuEntries(
        context,
        ref,
        space,
        serverKey,
        moveTo: _railMoveToEntries(ref, ServerEntityKey(serverKey, space.id)),
      ),
      globalPosition: position,
      title: space.name,
    );
  }

  /// The folder's menu, as in other chat apps: mark its servers read, then its
  /// settings (name and colour), then delete.
  Future<void> _folderMenu(
    BuildContext context,
    WidgetRef ref,
    Offset? position,
  ) {
    final ctl = ref.read(settingsControllerProvider.notifier);
    final entries = <AccordMenuEntry>[
      AccordMenuEntry(
        label: 'Mark Server Folder As Read',
        onSelected: () {
          for (final member in spaces) {
            final serverKey = widget.connOf[member.key]?.serverKey ?? '';
            final channels =
                ref.read(
                  accordChannelsControllerProvider(serverKey, member.space.id),
                ) ??
                const <AccordChannel>[];
            for (final channel in channels) {
              if (channel.type == 'category') continue;
              markChannelRead(
                ref,
                channel.id,
                fallbackMessageId: channel.lastMessageId,
              );
            }
          }
        },
      ),
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        label: 'Folder Settings',
        onSelected: () => _showFolderSettings(context, ref),
      ),
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        label: 'Delete Folder',
        destructive: true,
        onSelected: () => ctl.deleteFolder(folder.id),
      ),
    ];
    return showAccordContextMenu(
      context,
      entries: entries,
      globalPosition: position,
      title: folder.name.isEmpty ? 'Folder' : folder.name,
    );
  }

  /// Name and colour in one dialog.
  Future<void> _showFolderSettings(BuildContext context, WidgetRef ref) async {
    const palette = <int>[
      0, // default
      0xFF5865F2,
      0xFF57F287,
      0xFFEB459E,
      0xFFFEE75C,
      0xFFED4245,
      0xFF88C0D0,
      0xFFFF7A45,
    ];
    final ctl = ref.read(settingsControllerProvider.notifier);
    final nameController = TextEditingController(text: folder.name);
    var color = folder.color ?? 0;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Folder Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Folder name'),
              ),
              const SizedBox(height: 16),
              const Text('Folder color'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final argb in palette)
                    ColorSwatchChip(
                      color: argb == 0 ? Colors.grey : Color(argb),
                      selected: argb == color,
                      onTap: () => setState(() => color = argb),
                      icon: argb == 0 ? AppIcons.clear : null,
                      iconSize: 16,
                      iconColor: Colors.white,
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      ctl.renameFolder(folder.id, nameController.text.trim());
      ctl.setFolderColor(folder.id, color == 0 ? null : color);
    }
    nameController.dispose();
  }
}

/// A folder header's visual, shared by the rail and its drag feedback: the
/// tinted square with up to four member icons while closed, the folder glyph
/// once open (or when no member is cached yet).
/// Resolve membership in persisted order before taking four, so missing cache
/// entries never consume a preview slot and cross-server IDs stay qualified.
class SpaceFolderIcon extends StatelessWidget {
  const SpaceFolderIcon({
    super.key,
    required this.folder,
    required this.spaces,
    this.cdnUrls = const {},
  });

  final SpaceFolder folder;
  final Map<String, AccordSpace> spaces;
  final Map<String, String?> cdnUrls;

  /// Side of one member miniature; four fit a tile with 3 px margins and a
  /// 2 px gutter.
  static const double miniatureSize = 16;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final folderColor = _folderColor(folder, colors);
    final members = folder.spaceIds.where(spaces.containsKey).take(4).toList();
    return Container(
      width: _kRailTileSize,
      height: _kRailTileSize,
      decoration: BoxDecoration(
        color: folderColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(_kRailActiveRadius),
      ),
      alignment: Alignment.center,
      child: !folder.collapsed || members.isEmpty
          ? Icon(AppIcons.folder, size: 20, color: folderColor)
          : Padding(
              padding: const EdgeInsets.all(3),
              child: Column(
                children: [
                  for (var row = 0; row < 2; row++) ...[
                    if (row > 0) const SizedBox(height: 2),
                    Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        for (var column = 0; column < 2; column++) ...[
                          if (column > 0) const SizedBox(width: 2),
                          if (row * 2 + column < members.length)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                miniatureSize / 2,
                              ),
                              child: ColoredBox(
                                color: colors.foreground,
                                child: _SpaceIconImage(
                                  space: spaces[members[row * 2 + column]]!,
                                  cdnUrl: cdnUrls[members[row * 2 + column]],
                                  size: miniatureSize,
                                ),
                              ),
                            )
                          else
                            const SizedBox.square(dimension: miniatureSize),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// A space icon shown inside an expanded folder. Like [_DraggableSpace] but its
/// drops are scoped to the folder: dragging it out onto a rail space pulls it
/// from the folder, and a space dropped on it lands before it within the folder.
class _FolderMemberTile extends StatelessWidget {
  const _FolderMemberTile({
    required this.space,
    required this.entityKey,
    required this.conn,
    required this.selected,
    required this.onTap,
    required this.onDropBefore,
    required this.onMenu,
  });

  final AccordSpace space;
  final String entityKey;
  final _SpaceConn? conn;
  final bool selected;
  final VoidCallback onTap;

  /// A space [draggedSpaceId] was dropped on this member: place it before this
  /// member within the folder.
  final ValueChanged<String> onDropBefore;

  /// Open the member's management menu: anchored at [position] (desktop
  /// right-click) or as a sheet when it is null (touch long-press).
  final void Function(Offset? position) onMenu;

  @override
  Widget build(BuildContext context) {
    final icon = _SpaceIcon(
      space: space,
      selected: selected,
      cdnUrl: conn?.cdnUrl,
      serverKey: conn?.serverKey ?? '',
      onTap: onTap,
    );
    return DragTarget<_RailDrag>(
      onWillAcceptWithDetails: (d) => switch (d.data) {
        _SpaceDrag(:final spaceId) => spaceId != entityKey,
        _FolderDrag() => false,
      },
      onAcceptWithDetails: (d) {
        if (d.data case _SpaceDrag(:final spaceId)) {
          onDropBefore(spaceId);
        }
      },
      builder: (context, candidate, _) => Opacity(
        opacity: candidate.isNotEmpty ? 0.5 : 1,
        child: RailDraggable<_RailDrag>(
          data: _SpaceDrag(entityKey),
          tooltip: space.name,
          feedback: Material(
            color: Colors.transparent,
            child: _SpaceIcon(
              space: space,
              selected: false,
              cdnUrl: conn?.cdnUrl,
              serverKey: conn?.serverKey ?? '',
              onTap: () {},
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: icon),
          onMenu: onMenu,
          child: icon,
        ),
      ),
    );
  }
}
