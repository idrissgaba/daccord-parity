part of '../soundboard_picker.dart';

/// Rows of "Frequently Used" (two rows of three).
const int _kFrequentLimit = 6;

/// One block of the picker: a header, its cards, an entry in the rail.
class _Section {
  const _Section({
    required this.key,
    required this.title,
    required this.kind,
    required this.sounds,
    this.space,
    this.addCard = false,
    this.locked = false,
    this.lockedDivider = false,
  });

  final String key;
  final String title;
  final _SectionKind kind;
  final List<AccordSound> sounds;

  /// The space of a space section.
  final AccordSpace? space;

  /// Ends with the "Add Sound" card (this space, when we may add sounds).
  final bool addCard;

  /// Another space's sounds, which play only in that space.
  final bool locked;

  /// The first of the other spaces' sections: a lock divider goes above it.
  final bool lockedDivider;

  Widget headerIcon(BuildContext context, String? cdnUrl) {
    final colors = BonfireThemeExtension.of(context);
    return switch (kind) {
      _SectionKind.favorites => Icon(
        AppIcons.star,
        size: 16,
        color: colors.interactive,
      ),
      _SectionKind.frequent => Icon(
        AppIcons.schedule,
        size: 16,
        color: colors.interactive,
      ),
      _SectionKind.space => _SpaceGlyph(
        space: space!,
        cdnUrl: cdnUrl,
        size: 16,
      ),
    };
  }
}

enum _SectionKind { favorites, frequent, space }

class _SoundboardData {
  const _SoundboardData({required this.sections, required this.loading});

  final List<_Section> sections;

  /// This space's sounds have not arrived yet.
  final bool loading;
}

/// Whether the active user may add sounds to [spaceId] (Create Expressions)
/// or manage every sound there (Manage Soundboard).
({bool create, bool manage}) watchSoundboardRights(
  WidgetRef ref,
  String spaceId,
) {
  final space = ref.watch(
    spacesControllerProvider.select(
      (s) => s?.firstWhereOrNull((sp) => sp.id == spaceId),
    ),
  );
  final perms = ref.watchAccordPermissions(space, spaceId);
  final manage = accordHasPermission(perms, AccordPermission.manageSoundboard);
  return (
    create:
        manage ||
        accordHasPermission(perms, AccordPermission.createExpressions),
    manage: manage,
  );
}

/// Builds the picker's sections for a voice channel of [spaceId]: Favorites,
/// Frequently Used, this space (with "Add Sound" when allowed), then each
/// other space of the connection that has sounds — those only play in their
/// own space, so they show locked, as the reference client shows other
/// servers' sounds without Nitro. [query] (lower case) filters by name.
_SoundboardData _watchSoundboardSections(
  WidgetRef ref, {
  required String serverKey,
  required String spaceId,
  String query = '',
}) {
  final spaces = ref.watch(spacesControllerProvider) ?? const <AccordSpace>[];
  final current = spaces.firstWhereOrNull((s) => s.id == spaceId);
  final currentSounds = ref.watch(
    soundboardSoundsControllerProvider(serverKey, spaceId),
  );
  final others = <(AccordSpace, List<AccordSound>)>[
    for (final space in spaces)
      if (space.id != spaceId)
        (
          space,
          ref.watch(soundboardSoundsControllerProvider(serverKey, space.id)) ??
              const <AccordSound>[],
        ),
  ];
  final byKey = <String, AccordSound>{};
  void index(List<AccordSound>? sounds, String sid) {
    for (final s in sounds ?? const <AccordSound>[]) {
      final id = s.id;
      if (id == null) continue;
      s.spaceId ??= sid;
      byKey[soundSettingsKey(serverKey, id)] = s;
    }
  }

  index(currentSounds, spaceId);
  for (final (space, sounds) in others) {
    index(sounds, space.id);
  }

  final settings = ref.watch(
    settingsControllerProvider.select(
      (s) => (favorites: s.favoriteSounds, usage: s.soundUsage),
    ),
  );
  bool matches(AccordSound s) =>
      query.isEmpty || s.name.toLowerCase().contains(query);

  final favorites = [
    for (final key in settings.favorites)
      if (byKey[key] case final s? when matches(s)) s,
  ];
  final usage = settings.usage.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final frequent = [
    for (final e in usage)
      if (byKey[e.key] case final s? when matches(s)) s,
  ].take(_kFrequentLimit).toList();

  final rights = watchSoundboardRights(ref, spaceId);
  final sections = <_Section>[
    if (favorites.isNotEmpty)
      _Section(
        key: 'favorites',
        title: 'Favorites',
        kind: _SectionKind.favorites,
        sounds: favorites,
      ),
    if (frequent.isNotEmpty)
      _Section(
        key: 'frequent',
        title: 'Frequently Used',
        kind: _SectionKind.frequent,
        sounds: frequent,
      ),
  ];
  if (current != null) {
    final mine = (currentSounds ?? const <AccordSound>[]).where(matches);
    final addCard = rights.create && query.isEmpty;
    if (mine.isNotEmpty || addCard) {
      sections.add(
        _Section(
          key: 'space-$spaceId',
          title: current.name,
          kind: _SectionKind.space,
          space: current,
          sounds: mine.toList(),
          addCard: addCard,
        ),
      );
    }
  }
  var firstOther = true;
  for (final (space, sounds) in others) {
    final visible = sounds.where(matches).toList();
    if (visible.isEmpty) continue;
    sections.add(
      _Section(
        key: 'space-${space.id}',
        title: space.name,
        kind: _SectionKind.space,
        space: space,
        sounds: visible,
        locked: true,
        lockedDivider: firstOther,
      ),
    );
    firstOther = false;
  }
  return _SoundboardData(sections: sections, loading: currentSounds == null);
}

/// What the soundboard button's hover card suggests: the most played sounds
/// of this space, then the rest of its sounds, six at most.
List<AccordSound> watchSuggestedSounds(
  WidgetRef ref, {
  required String serverKey,
  required String spaceId,
}) {
  final sounds =
      ref.watch(soundboardSoundsControllerProvider(serverKey, spaceId)) ??
      const <AccordSound>[];
  final usage = ref.watch(
    settingsControllerProvider.select((s) => s.soundUsage),
  );
  int plays(AccordSound s) =>
      s.id == null ? 0 : usage[soundSettingsKey(serverKey, s.id!)] ?? 0;
  final ranked = [...sounds]..sort((a, b) => plays(b).compareTo(plays(a)));
  return ranked.take(6).toList();
}

/// A section title: icon, 14/600 name, and a caret that folds the section.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.collapsed,
    required this.onToggle,
  });

  final String title;
  final Widget icon;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 18 / 14,
                      color: colors.interactive,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: collapsed ? -0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    AppIcons.expandMore,
                    size: 16,
                    color: colors.interactive,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The line with a lock that separates this space's sounds from the other
/// spaces' ones, which play only in their own space.
class _LockDivider extends StatelessWidget {
  const _LockDivider();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Tooltip(
            message: 'These sounds play only in their own space',
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colors.raised,
                shape: BoxShape.circle,
                border: Border.all(color: colors.hairline),
              ),
              child: Icon(AppIcons.lock, size: 12, color: colors.dirtyWhite),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 48 px rail of section shortcuts on the picker's left edge.
class _SectionRail extends StatelessWidget {
  const _SectionRail({
    required this.sections,
    required this.selected,
    required this.cdnUrl,
    required this.onSelect,
  });

  final List<_Section> sections;
  final String? selected;
  final String? cdnUrl;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      width: 48,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
      ),
      child: ListView(
        padding: const EdgeInsets.only(top: 9),
        children: [
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RailEntry(
                key: Key('soundboard-rail-${section.key}'),
                section: section,
                selected: section.key == selected,
                cdnUrl: cdnUrl,
                onTap: () => onSelect(section.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailEntry extends StatelessWidget {
  const _RailEntry({
    super.key,
    required this.section,
    required this.selected,
    required this.cdnUrl,
    required this.onTap,
  });

  final _Section section;
  final bool selected;
  final String? cdnUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final Widget glyph = switch (section.kind) {
      _SectionKind.favorites => Icon(
        AppIcons.star,
        size: 20,
        color: colors.interactive,
      ),
      _SectionKind.frequent => Icon(
        AppIcons.schedule,
        size: 20,
        color: colors.interactive,
      ),
      _SectionKind.space => Stack(
        clipBehavior: Clip.none,
        children: [
          _SpaceGlyph(space: section.space!, cdnUrl: cdnUrl, size: 24),
          // Another space's sounds: a lock badge, as on the reference rail.
          if (section.locked)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colors.background,
                  shape: BoxShape.circle,
                ),
                child: Icon(AppIcons.lock, size: 8, color: colors.dirtyWhite),
              ),
            ),
        ],
      ),
    };
    return Tooltip(
      message: section.title,
      preferBelow: false,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (selected)
            Container(
              width: 3,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(2),
                ),
              ),
            ),
          Center(
            child: Material(
              color: selected ? colors.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(4),
                hoverColor: colors.hover,
                child: SizedBox.square(
                  dimension: 32,
                  child: Center(child: glyph),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A space's icon (or initial) at [size], rounded like the rail tiles.
class _SpaceGlyph extends StatelessWidget {
  const _SpaceGlyph({
    required this.space,
    required this.cdnUrl,
    required this.size,
  });

  final AccordSpace space;
  final String? cdnUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final url = accordSpaceIconUrl(space, cdnUrl);
    final fallback = ColoredBox(
      color: colors.primary,
      child: Center(
        child: Text(
          accordSpaceInitials(space.name),
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
