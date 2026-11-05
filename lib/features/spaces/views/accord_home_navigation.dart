part of 'accord_home.dart';

/// The home screen's app-wide keyboard shortcuts and the handlers behind the
/// MCP `navigate` tools. Split from [_AccordHomeScreenState] for size; both
/// only route into the screen's selection and open methods declared below.
mixin _HomeNavigation on ConsumerState<AccordHomeScreen> {
  bool get _memberListVisible;
  set _memberListVisible(bool value);
  void _selectSpace(String serverKey, String spaceId);
  Future<bool> _openChannel(String channelId, {required String spaceId});
  void _openSearchSelection(AccordSearchSelection selection);

  /// Places visited, for Alt+← / Alt+→ ("Navigate forward and backward in
  /// page history"), with the position walked to.
  final List<_NavPoint> _navHistory = [];
  int _navIndex = -1;
  bool _navReplaying = false;
  ProviderSubscription<OpenTab?>? _tabSubscription;

  @override
  void initState() {
    super.initState();
    QuickSwitcherLauncher.register(_openQuickSwitcher);
    dmHome.addListener(_recordDmVisit);
    _tabSubscription = ref.listenManual(
      openTabsControllerProvider.select((s) => s.activeTab),
      (_, tab) => _recordTabVisit(tab),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    QuickSwitcherLauncher.unregister(_openQuickSwitcher);
    dmHome.removeListener(_recordDmVisit);
    _tabSubscription?.close();
    super.dispose();
  }

  void _recordTabVisit(OpenTab? tab) {
    if (tab == null || dmHome.active) return;
    _recordVisit(
      _NavPoint(tab.serverKey, tab.channelId, spaceId: tab.spaceId),
    );
  }

  void _recordDmVisit() {
    final channel = dmHome.channel;
    final key = ref.read(connectionsControllerProvider).activeKey;
    if (!dmHome.active || channel == null || key == null) return;
    _recordVisit(_NavPoint(key, channel.id, dm: channel));
  }

  void _recordVisit(_NavPoint point) {
    QuickSwitcherHistory.visit(
      quickSwitchKey(QuickSwitchKind.textChannel, point.serverKey, point.id),
    );
    if (_navReplaying) return;
    if (_navIndex >= 0 && _navHistory[_navIndex].sameAs(point)) return;
    _navHistory
      ..removeRange(_navIndex + 1, _navHistory.length)
      ..add(point);
    if (_navHistory.length > 50) _navHistory.removeAt(0);
    _navIndex = _navHistory.length - 1;
  }

  Future<void> _walkHistory(int step) async {
    final target = _navIndex + step;
    if (target < 0 || target >= _navHistory.length) return;
    _navIndex = target;
    final point = _navHistory[target];
    _navReplaying = true;
    try {
      final dm = point.dm;
      if (dm != null) {
        _activateConnection(point.serverKey);
        dmHome.open(dm);
      } else if (point.spaceId case final spaceId?) {
        _selectSpace(point.serverKey, spaceId);
        await _openChannel(point.id, spaceId: spaceId);
      }
    } finally {
      _navReplaying = false;
    }
  }

  void _activateConnection(String serverKey) {
    if (ref.read(connectionsControllerProvider).activeKey != serverKey) {
      ref.read(accordAuthProvider.notifier).setActiveServer(serverKey);
    }
  }

  /// The place on screen, as a switcher key (left out of "Previous Channels").
  String? _currentPlaceKey() {
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    if (activeKey == null) return null;
    final id = dmHome.active
        ? dmHome.channel?.id
        : mcpHomeBridge.state.channelId;
    return id == null
        ? null
        : quickSwitchKey(QuickSwitchKind.textChannel, activeKey, id);
  }

  /// Ctrl+K and "Find or start a conversation": opens the switcher and goes
  /// where the pick leads.
  Future<void> _openQuickSwitcher() async {
    final pick = await showQuickSwitcher(context, current: _currentPlaceKey());
    if (pick == null || !mounted) return;
    QuickSwitcherHistory.visit(pick.key);
    switch (pick.kind) {
      case QuickSwitchKind.textChannel:
        _selectSpace(pick.serverKey, pick.spaceId!);
        await _openChannel(pick.id, spaceId: pick.spaceId!);
      case QuickSwitchKind.voiceChannel:
        // As a click on the channel list: on desktop it joins (or, when
        // already in it, opens the call); on touch it opens the lobby.
        final spaceId = pick.spaceId!;
        final voice = ref.read(voiceControllerProvider);
        if (shouldUseDesktopLayout(context) && voice.channelId != pick.id) {
          if (ref.read(connectionsControllerProvider).activeKey !=
              pick.serverKey) {
            _selectSpace(pick.serverKey, spaceId);
          }
          await ref
              .read(voiceControllerProvider.notifier)
              .join(pick.id, spaceId);
        } else {
          _selectSpace(pick.serverKey, spaceId);
          await _openChannel(pick.id, spaceId: spaceId);
        }
      case QuickSwitchKind.space:
        _selectSpace(pick.serverKey, pick.id);
      case QuickSwitchKind.dm:
        _activateConnection(pick.serverKey);
        dmHome.open(pick.channel);
      case QuickSwitchKind.user:
        _activateConnection(pick.serverKey);
        await openAccordDirectMessage(context, ref, pick.id);
    }
  }

  /// The focused text field's value, or null when no text field has focus.
  TextEditingValue? _focusedText() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null || !focusContext.mounted) return null;
    final editable = focusContext.widget is EditableText
        ? focusContext.widget as EditableText
        : focusContext.findAncestorWidgetOfExactType<EditableText>();
    return editable?.controller.value;
  }

  /// Whether a shortcut may run now. Shortcuts that share a chord (Esc)
  /// apply one at a time; those that only make sense with something on
  /// screen do nothing (and leave the key alone) without it.
  bool _applies(HomeShortcut shortcut, TextEditingValue? text) {
    final call = ref.read(callControllerProvider);
    final hasSelection = text != null && !text.selection.isCollapsed;
    final hasText = text != null && text.text.isNotEmpty;
    switch (shortcut) {
      // A selection keeps Ctrl+I / Ctrl+U for italic and underline.
      case HomeShortcut.toggleInbox:
      case HomeShortcut.toggleMembers:
        return !hasSelection &&
            (shortcut != HomeShortcut.toggleInbox ||
                _keyedElement(const Key('home-title-bar-inbox')) != null);
      // Alt+arrows move the caret by word in a field that has text.
      case HomeShortcut.historyBack:
      case HomeShortcut.historyForward:
      case HomeShortcut.previousUnread:
      case HomeShortcut.nextUnread:
        return !hasText;
      case HomeShortcut.answerCall:
      case HomeShortcut.declineCall:
        return call.incoming != null;
      case HomeShortcut.startDmCall:
        return dmHome.active && dmHome.channel != null;
      case HomeShortcut.togglePins:
        return _keyedElement(const Key('channel-header-pins')) != null;
      case HomeShortcut.toggleSoundboard:
        return _keyedElement(const Key('voice-bar-soundboard')) != null;
      default:
        return true;
    }
  }

  /// App-wide shortcuts (Ctrl+K, Alt+↑/↓, Ctrl+Shift+M, …). A hardware-level
  /// handler rather than a `Shortcuts` widget so they work whatever has
  /// focus, including nothing at all after a click on the channel list. Only
  /// while this screen is the current route: a dialog's own keys (the quick
  /// switcher's ↑/↓) must not reach here. Esc and Shift+Esc mark read
  /// without consuming the key, so a field still gets its Escape.
  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final mods = HardwareKeyboard.instance;
    final control = mods.isControlPressed || mods.isMetaPressed;
    final settings = ref.read(settingsControllerProvider);
    final matches = matchHomeShortcuts(
      pressed: event.logicalKey,
      control: control,
      shift: mods.isShiftPressed,
      alt: mods.isAltPressed,
      physicalPressed: event.physicalKey.usbHidUsage,
      custom: settings.keybinds,
      disabledDefaults: settings.disabledDefaultKeybinds,
    );
    final text = _focusedText();
    for (final shortcut in matches) {
      if (!_applies(shortcut, text)) continue;
      unawaited(_runShortcut(shortcut));
      return !passThroughShortcuts.contains(shortcut);
    }
    // Any other key typed outside a text field goes to the composer.
    final character = event.character;
    if (text == null &&
        !control &&
        !mods.isAltPressed &&
        character != null &&
        character.trim().isNotEmpty &&
        !character.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      return requestComposerShortcut(ComposerShortcut.focus, text: character);
    }
    return false;
  }

  /// The element of the widget keyed [key] under this screen, or null.
  Element? _keyedElement(Key key) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  /// Presses the button keyed [key] (a header or bar button this screen
  /// does not own), as a click would.
  bool _pressKeyed(Key key) {
    final element = _keyedElement(key);
    if (element == null) return false;
    VoidCallback? action;
    void visit(Element e) {
      if (action != null) return;
      final widget = e.widget;
      if (widget is IconButton) {
        action = widget.onPressed;
      } else if (widget is InkWell) {
        action = widget.onTap;
      } else if (widget is GestureDetector) {
        action = widget.onTap;
      }
      if (action == null) e.visitChildren(visit);
    }

    visit(element);
    action?.call();
    return action != null;
  }

  /// The channels of the space on show, in list order.
  List<String> _shownChannelIds(String activeKey) {
    final spaceId = mcpHomeBridge.state.spaceId;
    if (spaceId == null) return const [];
    final channels =
        ref.read(accordChannelsControllerProvider(activeKey, spaceId)) ??
        const <AccordChannel>[];
    return orderedNavigableChannelIds(channels);
  }

  Future<void> _runShortcut(HomeShortcut shortcut) async {
    final shown = mcpHomeBridge.state;
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    switch (shortcut) {
      case HomeShortcut.quickSwitcher:
        await _openQuickSwitcher();
      case HomeShortcut.previousChannel:
      case HomeShortcut.nextChannel:
        final spaceId = shown.spaceId;
        if (spaceId == null || activeKey == null) return;
        final next = adjacentId(
          _shownChannelIds(activeKey),
          shown.channelId,
          forward: shortcut == HomeShortcut.nextChannel,
        );
        if (next != null) await _openChannel(next, spaceId: spaceId);
      case HomeShortcut.previousUnread:
      case HomeShortcut.nextUnread:
      case HomeShortcut.previousMention:
      case HomeShortcut.nextMention:
        final spaceId = shown.spaceId;
        if (spaceId == null || activeKey == null || dmHome.active) return;
        final readState = ref.read(readStateControllerProvider(activeKey));
        final mentions =
            shortcut == HomeShortcut.previousMention ||
            shortcut == HomeShortcut.nextMention;
        final next = adjacentMatchingId(
          _shownChannelIds(activeKey),
          shown.channelId,
          forward:
              shortcut == HomeShortcut.nextUnread ||
              shortcut == HomeShortcut.nextMention,
          test: (id) => mentions
              ? readState.mentionCount(id) > 0
              : readState.isUnread(id),
        );
        if (next != null) await _openChannel(next, spaceId: spaceId);
      case HomeShortcut.previousSpace:
      case HomeShortcut.nextSpace:
        final current = activeKey == null || shown.spaceId == null
            ? null
            : ServerEntityKey(activeKey, shown.spaceId!).encoded;
        final next = adjacentId(
          _railSpaceKeys(),
          current,
          forward: shortcut == HomeShortcut.nextSpace,
        );
        final target = next == null ? null : ServerEntityKey.tryDecode(next);
        if (target != null) _selectSpace(target.serverKey, target.entityId);
      case HomeShortcut.historyBack:
        await _walkHistory(-1);
      case HomeShortcut.historyForward:
        await _walkHistory(1);
      case HomeShortcut.currentCall:
        final voice = ref.read(voiceControllerProvider);
        final channelId = voice.channelId;
        if (channelId == null) return;
        final spaceId = voice.spaceId;
        if (spaceId == null) {
          await showAccordDmCall(context, ref, channelId);
        } else {
          _selectSpace(voice.serverKey ?? activeKey ?? '', spaceId);
          await _openChannel(channelId, spaceId: spaceId);
        }
      case HomeShortcut.toggleDmHome:
        if (dmHome.active) {
          final tab = ref.read(openTabsControllerProvider).activeTab;
          if (tab != null) {
            _selectSpace(tab.serverKey, tab.spaceId);
          } else {
            dmHome.leave();
          }
        } else {
          dmHome.open(dmHome.channel);
        }
      case HomeShortcut.createOrJoinServer:
        await showAddServerDialog(context);
      // While in a call on Windows the voice controller watches these chords
      // system-wide and has already toggled.
      case HomeShortcut.toggleMute:
        final voice = ref.read(voiceControllerProvider.notifier);
        if (!voice.watchesVoiceShortcutsGlobally) voice.toggleMute();
      case HomeShortcut.toggleDeafen:
        final voice = ref.read(voiceControllerProvider.notifier);
        if (!voice.watchesVoiceShortcutsGlobally) voice.toggleDeafen();
      case HomeShortcut.answerCall:
        final channelId = await ref
            .read(callControllerProvider.notifier)
            .acceptIncoming();
        if (channelId != null && mounted) {
          await showAccordDmCall(context, ref, channelId);
        }
      case HomeShortcut.declineCall:
        await ref.read(callControllerProvider.notifier).declineIncoming();
      case HomeShortcut.startDmCall:
        final channel = dmHome.channel;
        if (channel == null) return;
        await ref.read(callControllerProvider.notifier).startCall(channel);
      case HomeShortcut.toggleSoundboard:
        _pressKeyed(const Key('voice-bar-soundboard'));
      case HomeShortcut.markSpaceRead:
        if (activeKey == null || shown.spaceId == null || dmHome.active) {
          return;
        }
        for (final channel
            in ref.read(
                  accordChannelsControllerProvider(activeKey, shown.spaceId!),
                ) ??
                const <AccordChannel>[]) {
          if (channel.type == 'category') continue;
          markChannelRead(
            ref,
            channel.id,
            fallbackMessageId: channel.lastMessageId,
          );
        }
      case HomeShortcut.markChannelRead:
        final channelId = dmHome.active
            ? dmHome.channel?.id
            : shown.channelId;
        if (channelId != null) markChannelRead(ref, channelId);
      case HomeShortcut.createGroupDm:
        if (!dmHome.active) {
          dmHome.open(dmHome.channel);
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
        }
        _pressKeyed(const Key('dm-create'));
      case HomeShortcut.togglePins:
        _pressKeyed(const Key('channel-header-pins'));
      case HomeShortcut.toggleInbox:
        _pressKeyed(const Key('home-title-bar-inbox'));
      case HomeShortcut.toggleMembers:
        setState(() => _memberListVisible = !_memberListVisible);
      case HomeShortcut.emojiPicker:
        requestComposerShortcut(ComposerShortcut.emoji);
      case HomeShortcut.gifPicker:
        requestComposerShortcut(ComposerShortcut.gif);
      case HomeShortcut.stickerPicker:
        requestComposerShortcut(ComposerShortcut.sticker);
      case HomeShortcut.uploadFile:
        requestComposerShortcut(ComposerShortcut.upload);
      case HomeShortcut.copyChannelLink:
        final spaceId = shown.spaceId;
        final channelId = shown.channelId;
        if (spaceId == null || channelId == null || dmHome.active) return;
        await Clipboard.setData(
          ClipboardData(
            text: channelLink(spaceId: spaceId, channelId: channelId),
          ),
        );
        if (mounted) showInfoSnack(context, 'Link copied');
      case HomeShortcut.getHelp:
        await launchUrl(
          Uri.parse(kDaccordHelpUrl),
          mode: LaunchMode.externalApplication,
        );
      case HomeShortcut.search:
        final spaceId = shown.spaceId;
        if (spaceId == null || dmHome.active) return;
        final selection = await showAccordSearch(context, spaceId: spaceId);
        if (mounted && selection != null) _openSearchSelection(selection);
      case HomeShortcut.openSettings:
        context.push('/settings');
      case HomeShortcut.showShortcuts:
        await showKeyboardShortcutsDialog(context);
    }
  }

  /// The rail's spaces (every connection, minus hidden ones) as encoded
  /// entity keys, in the order the rail draws them.
  List<String> _railSpaceKeys() {
    final connections = ref.read(connectionsControllerProvider);
    final settings = ref.read(settingsControllerProvider);
    final live = ref.read(spacesControllerProvider);
    final keys = <String>[];
    for (final conn in connections.connections) {
      final spaces = conn.key == connections.activeKey
          ? (live ?? conn.spaces)
          : conn.spaces;
      for (final space in spaces) {
        final key = ServerEntityKey(conn.key, space.id).encoded;
        if (!settings.hiddenSpaces.contains(key)) keys.add(key);
      }
    }
    return orderBySavedOrder(keys, settings.spaceOrder);
  }

  /// Navigation handlers the local MCP server's `navigate` tools delegate to.
  /// Each receives the argument map already resolved by the tools layer and
  /// returns an MCP result map.
  Map<String, McpNavHandler> _mcpNavHandlers() => {
    'select_space': (args) async {
      _selectSpace(args['server_key'] as String, args['space_id'] as String);
      return {'ok': true};
    },
    'select_channel': (args) async {
      await _openChannel(
        args['channel_id'] as String,
        spaceId: args['space_id'] as String,
      );
      return {'ok': true};
    },
    'open_dm': (args) async {
      if (!mounted) return _mcpUnmounted;
      showAccordDirectMessages(context);
      return {'ok': true};
    },
    'open_settings': (args) async {
      if (!mounted) return _mcpUnmounted;
      context.push('/settings');
      return {'ok': true};
    },
    'open_discovery': (args) async {
      if (!mounted) return _mcpUnmounted;
      showAccordDiscovery(context);
      return {'ok': true};
    },
    'open_thread': (args) async {
      if (!mounted) return _mcpUnmounted;
      final channelId = args['channel_id'] as String;
      final messageId = args['message_id'] as String;
      final root = ref
          .read(
            accordMessagesControllerProvider(
              ref.readActiveServerKey() ?? '',
              channelId,
            ),
          )
          ?.firstWhereOrNull((m) => m.id == messageId);
      if (root == null) return {'error': 'Message not loaded'};
      showAccordThread(context, channelId: channelId, root: root);
      return {'ok': true};
    },
    // Reveals the *current* call's channel; it never joins one (matching the
    // rest of the app after #202 — navigation is never a connect). It stays an
    // error when nothing is connected rather than silently joining something:
    // `select_channel` already opens any voice channel's lobby.
    'open_voice_view': (args) async {
      if (!mounted) return _mcpUnmounted;
      final voice = ref.read(voiceControllerProvider);
      if (!voice.isConnected) {
        return {'error': 'Not connected to a voice channel'};
      }
      await _openChannel(voice.channelId!, spaceId: voice.spaceId!);
      return {'ok': true};
    },
    'toggle_member_list': (args) async {
      if (!mounted) return _mcpUnmounted;
      setState(() => _memberListVisible = !_memberListVisible);
      return {'ok': true, 'visible': _memberListVisible};
    },
    'toggle_search': (args) async {
      if (!mounted) return _mcpUnmounted;
      final spaceId = mcpHomeBridge.state.spaceId;
      if (spaceId == null || spaceId.isEmpty) {
        return {'error': 'No space selected'};
      }
      final selection = await showAccordSearch(context, spaceId: spaceId);
      if (mounted && selection != null) _openSearchSelection(selection);
      return {'ok': true};
    },
  };

  static const Map<String, dynamic> _mcpUnmounted = {
    'error': 'Home screen not mounted',
  };
}

/// A place in the navigation history: a space channel or a DM conversation.
class _NavPoint {
  const _NavPoint(this.serverKey, this.id, {this.spaceId, this.dm});

  final String serverKey;
  final String id;
  final String? spaceId;
  final AccordChannel? dm;

  bool sameAs(_NavPoint other) =>
      other.serverKey == serverKey && other.id == id;
}
