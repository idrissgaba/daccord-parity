part of 'message_pane.dart';

/// One reaction as the reference client draws it: a 30 px pill (emoji 20,
/// count 16/600) with an 8 px radius; yours is washed and outlined in the
/// accent. Hovering it names who reacted, in a raised tooltip with the emoji
/// at 48 px.
class _ReactionPill extends StatefulWidget {
  const _ReactionPill({
    required this.reaction,
    required this.onTap,
    required this.onShowReactors,
    this.reactorNames,
    this.imageUrl,
    this.trustedMediaBaseUrl,
    this.superReaction = false,
  });

  final AccordReaction reaction;

  /// Drawn as a super reaction: a glowing gradient border and a sparkle.
  final bool superReaction;
  final VoidCallback onTap;

  /// Long-press / right-click: reveal who reacted.
  final VoidCallback onShowReactors;

  /// Loads the reactors' names for the hover tooltip; null shows no tooltip.
  final Future<List<String>> Function()? reactorNames;

  /// Resolved image URL for a custom-emoji reaction; null for unicode.
  final String? imageUrl;
  final String? trustedMediaBaseUrl;

  @override
  State<_ReactionPill> createState() => _ReactionPillState();
}

class _ReactionPillState extends State<_ReactionPill> {
  List<String>? _names;
  bool _loading = false;

  void _loadNames() {
    final load = widget.reactorNames;
    if (load == null || _loading) return;
    _loading = true;
    load().then((names) {
      if (!mounted) return;
      setState(() {
        _names = names;
        _loading = false;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _ReactionPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reaction.count != widget.reaction.count) {
      _names = null;
      _loading = false;
    }
  }

  /// "A, B and C" — the reference client's wording, capped at three names.
  static String _joinNames(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} and ${names[1]}';
    if (names.length == 3) return '${names[0]}, ${names[1]} and ${names[2]}';
    return '${names[0]}, ${names[1]}, ${names[2]} and ${names.length - 3} '
        'other${names.length - 3 == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final reaction = widget.reaction;
    final rawName = reaction.emoji['name']?.toString() ?? '';
    final rawId = reaction.emoji['id']?.toString();
    // A custom emoji whose source didn't split it arrives as name=`name:id`,
    // id=null; recover the id so we render the image instead of literal text.
    final parsed = parseEmojiToken(rawName);
    final id = rawId ?? parsed.id;
    final name = rawId != null ? rawName : parsed.name;
    final mine = reaction.includesMe;
    final superReaction = widget.superReaction;
    final glyph = id == null ? resolveEmojiGlyph(name) : null;
    Widget emoji(double size) => id != null && widget.imageUrl != null
        ? MessageMediaGate(
            source: widget.imageUrl,
            trustedBaseUrl: widget.trustedMediaBaseUrl,
            allowExternalConsent: false,
            blockedPlaceholder: Text(
              name,
              style: TextStyle(fontSize: size * 0.7),
            ),
            builder: (_, safeUrl) => CachedNetworkImage(
              imageUrl: safeUrl,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) =>
                  Text(name, style: TextStyle(fontSize: size * 0.7)),
            ),
          )
        // Unicode reaction: `name` is the shortcode (e.g. `hamburger`), not
        // the glyph — resolve it to the actual emoji character.
        : Text(
            glyph ?? name,
            style: TextStyle(fontSize: size * 0.8, height: 1),
          );
    final pill = Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: mine
            ? colors.primary.withValues(alpha: 0.24)
            : colors.selection.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: superReaction
              ? superReactionColor(colors)
              : (mine ? colors.primary : Colors.transparent),
          width: superReaction ? 1.5 : 1,
        ),
        boxShadow: superReaction
            ? [
                BoxShadow(
                  color: superReactionColor(
                    colors,
                  ).withValues(alpha: mine ? 0.55 : 0.3),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (superReaction) ...[
            Icon(
              AppIcons.autoAwesome,
              size: 12,
              color: superReactionColor(colors),
              semanticLabel: 'Super reaction',
            ),
            const SizedBox(width: 3),
          ],
          SizedBox(width: 20, height: 20, child: Center(child: emoji(20))),
          const SizedBox(width: 6),
          Text(
            '${reaction.count}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1,
              color: mine ? const Color(0xFFB9C8FF) : colors.dirtyWhite,
            ),
          ),
        ],
      ),
    );
    final label = id == null ? ':${emojiShortName(name)}:' : ':$name:';
    final names = _names;
    final who = names == null
        ? '…'
        : names.isEmpty
        ? '${reaction.count} ${reaction.count == 1 ? 'person' : 'people'}'
        : _joinNames(names);
    return MouseRegion(
      onEnter: (_) => _loadNames(),
      child: Tooltip(
        waitDuration: const Duration(milliseconds: 300),
        richMessage: widget.reactorNames == null
            ? null
            : TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(child: emoji(48)),
                      ),
                    ),
                  ),
                  TextSpan(text: '$label reacted by $who'),
                ],
              ),
        message: widget.reactorNames == null ? '' : null,
        padding: const EdgeInsets.all(16),
        verticalOffset: 24,
        preferBelow: false,
        decoration: BoxDecoration(
          color: popoverSurfaceColor(colors),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.08),
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        textStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colors.dirtyWhite,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            onLongPress: widget.onShowReactors,
            onSecondaryTap: widget.onShowReactors,
            child: pill,
          ),
        ),
      ),
    );
  }
}

/// The "add another reaction" pill shown after the reactions while the
/// message is hovered: 34×30, the smiley at 18 px.
class _AddReactionPill extends StatelessWidget {
  const _AddReactionPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Tooltip(
      message: 'Add Reaction',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: colors.selection.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: const Key('add-reaction-pill'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 30,
            child: Icon(
              AppIcons.addReactionOutlined,
              size: 18,
              color: colors.interactive,
            ),
          ),
        ),
      ),
    );
  }
}

/// A popup listing the users who reacted with a given emoji, lazy-loaded when
/// opened (reactor lists aren't prefetched per message). Ports the reference
/// client's reactor reveal.
class _ReactorsDialog extends ConsumerStatefulWidget {
  const _ReactorsDialog({
    required this.channelId,
    required this.messageId,
    required this.emojiName,
    required this.emojiId,
  });

  final String channelId;
  final String messageId;
  final String emojiName;
  final String? emojiId;

  @override
  ConsumerState<_ReactorsDialog> createState() => _ReactorsDialogState();
}

class _ReactorsDialogState extends ConsumerState<_ReactorsDialog> {
  List<AccordUser>? _users;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = ref.accordClient;
    if (client == null) {
      setState(() => _users = const []);
      return;
    }
    final users = await ref
        .read(
          accordMessagesControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.channelId,
          ).notifier,
        )
        .reactionUsers(
          client,
          widget.messageId,
          widget.emojiName,
          emojiId: widget.emojiId,
        );
    if (mounted) setState(() => _users = users);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final cdnUrl = ref.watchCdnUrl();
    final users = _users;
    return AlertDialog(
      title: Text(
        widget.emojiId == null
            ? 'Reacted with ${resolveEmojiGlyph(widget.emojiName)}'
            : 'Reacted with :${widget.emojiName}:',
      ),
      content: SizedBox(
        width: 300,
        child: users == null
            ? const SizedBox(height: 80, child: LoadingView())
            : users.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No one yet.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: colors.gray),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final user in users)
                    _ReactorTile(user: user, cdnUrl: cdnUrl),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ReactorTile extends StatelessWidget {
  const _ReactorTile({required this.user, required this.cdnUrl});

  final AccordUser user;
  final String? cdnUrl;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = accordAvatarUrl(user, cdnUrl);
    return ListTile(
      dense: true,
      leading: AccordMemberAvatar(
        avatarUrl: avatarUrl,
        initial: accordInitial(accordUserName(user, fallback: '?')),
        backgroundColor: accordAvatarColor(user, user.id),
        radius: 14,
      ),
      title: Text(
        accordUserName(user, fallback: user.id),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// The accent of super reactions.
Color superReactionColor(BonfireThemeExtension colors) =>
    Color.lerp(colors.primary, const Color(0xFFFFC857), 0.5)!;

/// A super reaction pill that bursts (a quick pop) whenever its count grows.
class _SuperReactionPill extends StatefulWidget {
  const _SuperReactionPill({
    super.key,
    required this.superReaction,
    required this.child,
  });

  final AccordSuperReaction superReaction;
  final Widget Function(AccordReaction reaction) child;

  @override
  State<_SuperReactionPill> createState() => _SuperReactionPillState();
}

class _SuperReactionPillState extends State<_SuperReactionPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.45), weight: 35),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.45,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_burst);

  @override
  void initState() {
    super.initState();
    if (widget.superReaction.me) _burst.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _SuperReactionPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.superReaction.count > oldWidget.superReaction.count) {
      _burst.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sup = widget.superReaction;
    final token = parseEmojiToken(sup.emoji);
    final reaction = AccordReaction(
      emoji: {'id': token.id, 'name': token.name},
      count: sup.count,
      includesMe: sup.me,
    );
    return ScaleTransition(scale: _scale, child: widget.child(reaction));
  }
}
