import 'dart:async';

import 'package:client/api/api_client.dart';
import 'package:client/src/models/server_models.dart';
import 'package:client/src/widgets/error_banner.dart';
import 'package:flutter/material.dart';

typedef ActivityErrorFormatter = String Function(ApiError error);
typedef ActivityNotifier = void Function(String message);

class ActivitySidebar extends StatefulWidget {
  const ActivitySidebar({
    super.key,
    required this.apiClient,
    required this.workspaceId,
    required this.currentFlowRef,
    required this.selectedProcessorRef,
    required this.onNotify,
    required this.formatApiError,
    required this.isActive,
  });

  final ApiClient apiClient;
  final String? workspaceId;
  final CollaborationRef? currentFlowRef;
  final CollaborationRef? selectedProcessorRef;
  final ActivityNotifier onNotify;
  final ActivityErrorFormatter formatApiError;
  final bool isActive;

  @override
  State<ActivitySidebar> createState() => _ActivitySidebarState();
}

class _ActivitySidebarState extends State<ActivitySidebar> {
  bool _activityLoaded = false;
  bool _channelsLoading = false;
  String? _channelsError;
  List<ChannelListItem> _channels = const <ChannelListItem>[];
  String? _selectedChannelDocId;

  bool _messagesLoading = false;
  String? _messagesError;
  List<MessageListItem> _messages = const <MessageListItem>[];
  final ScrollController _messagesScrollController = ScrollController();
  final TextEditingController _composerController = TextEditingController();
  bool _postingMessage = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      unawaited(_ensureLoaded());
    }
  }

  @override
  void dispose() {
    _messagesScrollController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ActivitySidebar oldWidget) {
    super.didUpdateWidget(oldWidget);

    final workspaceChanged = oldWidget.workspaceId != widget.workspaceId;
    final apiClientChanged = oldWidget.apiClient != widget.apiClient;
    if (workspaceChanged || apiClientChanged) {
      setState(_resetState);
      if (widget.isActive) {
        unawaited(_ensureLoaded());
      }
      return;
    }

    if (!oldWidget.isActive && widget.isActive) {
      unawaited(_ensureLoaded());
    }
  }

  void _resetState() {
    _activityLoaded = false;
    _channelsLoading = false;
    _channelsError = null;
    _channels = const <ChannelListItem>[];
    _selectedChannelDocId = null;
    _messagesLoading = false;
    _messagesError = null;
    _messages = const <MessageListItem>[];
    _composerController.clear();
    _postingMessage = false;
  }

  Future<void> _ensureLoaded() async {
    if (widget.workspaceId == null) {
      if (!mounted) {
        return;
      }
      setState(_resetState);
      return;
    }
    if (_activityLoaded) {
      if (_selectedChannelDocId != null &&
          _messages.isEmpty &&
          !_messagesLoading) {
        await _loadMessagesForSelectedChannel();
      }
      return;
    }

    await _loadChannels();
    await _loadMessagesForSelectedChannel();
    if (!mounted) {
      return;
    }
    setState(() {
      _activityLoaded = true;
    });
  }

  Future<void> _loadChannels() async {
    final workspaceId = widget.workspaceId;
    if (workspaceId == null) {
      if (!mounted) {
        return;
      }
      setState(_resetState);
      return;
    }

    if (mounted) {
      setState(() {
        _channelsLoading = true;
        _channelsError = null;
      });
    }

    try {
      final channels = await widget.apiClient.getChannels(
        workspaceId: workspaceId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _channels = channels;
        if (_selectedChannelDocId == null ||
            !_channels.any((item) => item.docId == _selectedChannelDocId)) {
          _selectedChannelDocId = _channels.isEmpty
              ? null
              : _channels.first.docId;
        }
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _channelsError = widget.formatApiError(error);
        _channels = const <ChannelListItem>[];
        _selectedChannelDocId = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _channelsLoading = false;
        });
      }
    }
  }

  Future<void> _onChannelSelected(String channelDocId) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedChannelDocId = channelDocId;
      _messages = const <MessageListItem>[];
      _messagesError = null;
      _composerController.clear();
    });
    await _loadMessagesForSelectedChannel();
  }

  Future<void> _loadMessagesForSelectedChannel() async {
    final channelDocId = _selectedChannelDocId;
    if (channelDocId == null || channelDocId.trim().isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messagesLoading = false;
        _messagesError = null;
        _messages = const <MessageListItem>[];
      });
      return;
    }

    if (mounted) {
      setState(() {
        _messagesLoading = true;
        _messagesError = null;
      });
    }

    try {
      final messages = await widget.apiClient.getMessages(
        channelDocId: channelDocId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = messages;
      });
      _scrollMessagesToBottom();
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messagesError = widget.formatApiError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _messagesLoading = false;
        });
      }
    }
  }

  void _scrollMessagesToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messagesScrollController.hasClients) {
        return;
      }
      _messagesScrollController.animateTo(
        _messagesScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  ChannelListItem? _selectedChannel() {
    final channelDocId = _selectedChannelDocId;
    if (channelDocId == null) {
      return null;
    }
    for (final item in _channels) {
      if (item.docId == channelDocId) {
        return item;
      }
    }
    return null;
  }

  bool _hasSameRef(List<CollaborationRef> refs, CollaborationRef candidate) {
    for (final item in refs) {
      if (item.kind == candidate.kind &&
          item.id == candidate.id &&
          item.docId == candidate.docId &&
          item.nodeId == candidate.nodeId &&
          item.flowDocId == candidate.flowDocId) {
        return true;
      }
    }
    return false;
  }

  Future<void> _showCreateChannelDialog() async {
    final workspaceId = widget.workspaceId;
    if (workspaceId == null) {
      widget.onNotify('Select or create a workspace first.');
      return;
    }

    final selectedChannel = _selectedChannel();
    final nameController = TextEditingController();
    final topicController = TextEditingController();
    var scope = selectedChannel?.scope ?? 'team';

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('New Channel'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: scope,
                      decoration: const InputDecoration(
                        labelText: 'Scope',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'personal',
                          child: Text('personal'),
                        ),
                        DropdownMenuItem(value: 'team', child: Text('team')),
                        DropdownMenuItem(value: 'org', child: Text('org')),
                        DropdownMenuItem(
                          value: 'public_read',
                          child: Text('public_read'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          scope = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Channel name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: topicController,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Topic / description (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (submitted != true) {
      nameController.dispose();
      topicController.dispose();
      return;
    }

    final name = nameController.text.trim();
    final topic = topicController.text.trim();
    nameController.dispose();
    topicController.dispose();

    if (name.isEmpty) {
      widget.onNotify('Channel name cannot be empty');
      return;
    }

    try {
      final created = await widget.apiClient.createChannel(
        workspaceId: workspaceId,
        scope: scope,
        name: name,
        kind: 'workspace',
        topic: topic,
      );
      await _loadChannels();
      if (mounted) {
        setState(() {
          _selectedChannelDocId = created.docId;
        });
      }
      await _loadMessagesForSelectedChannel();
      if (!mounted) {
        return;
      }
      setState(() {
        _activityLoaded = true;
      });
      widget.onNotify('Channel created');
    } on ApiError catch (error) {
      widget.onNotify(widget.formatApiError(error));
    }
  }

  Future<void> _showRenameChannelDialog() async {
    final selectedChannel = _selectedChannel();
    if (selectedChannel == null) {
      widget.onNotify('Select a channel first.');
      return;
    }

    final nameController = TextEditingController(text: selectedChannel.name);
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename Channel'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Channel name',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    final name = nameController.text.trim();
    nameController.dispose();

    if (submitted != true) {
      return;
    }
    if (name.isEmpty) {
      widget.onNotify('Channel name cannot be empty');
      return;
    }

    try {
      await widget.apiClient.patchChannel(
        channelDocId: selectedChannel.docId,
        name: name,
      );
      await _loadChannels();
      widget.onNotify('Channel renamed');
    } on ApiError catch (error) {
      widget.onNotify(widget.formatApiError(error));
    }
  }

  Future<void> _deleteSelectedChannel() async {
    final selectedChannel = _selectedChannel();
    if (selectedChannel == null) {
      widget.onNotify('Select a channel first.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Channel'),
          content: Text(
            'Delete "${selectedChannel.name.isEmpty ? '(untitled channel)' : selectedChannel.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.apiClient.deleteChannel(
        channelDocId: selectedChannel.docId,
      );
      await _loadChannels();
      await _loadMessagesForSelectedChannel();
      widget.onNotify('Channel deleted');
    } on ApiError catch (error) {
      widget.onNotify(widget.formatApiError(error));
    }
  }

  Future<void> _handleChannelMenuAction(String value) async {
    switch (value) {
      case 'create':
        await _showCreateChannelDialog();
        break;
      case 'rename':
        await _showRenameChannelDialog();
        break;
      case 'delete':
        await _deleteSelectedChannel();
        break;
    }
  }

  Future<void> _submitInlineMessage() async {
    final workspaceId = widget.workspaceId;
    final channelDocId = _selectedChannelDocId;
    if (workspaceId == null) {
      widget.onNotify('Select or create a workspace first.');
      return;
    }
    if (channelDocId == null) {
      widget.onNotify('Create a channel before posting.');
      return;
    }

    final body = _composerController.text.trim();
    if (body.isEmpty) {
      return;
    }

    final selectedChannel = _selectedChannel();
    final refs = <CollaborationRef>[];
    final currentFlowRef = widget.currentFlowRef;
    final selectedProcessorRef = widget.selectedProcessorRef;
    if (currentFlowRef != null && !_hasSameRef(refs, currentFlowRef)) {
      refs.add(currentFlowRef);
    }
    if (selectedProcessorRef != null &&
        !_hasSameRef(refs, selectedProcessorRef)) {
      refs.add(selectedProcessorRef);
    }

    if (mounted) {
      setState(() {
        _postingMessage = true;
      });
    }

    try {
      await widget.apiClient.createMessage(
        workspaceId: workspaceId,
        scope: selectedChannel?.scope ?? 'team',
        channelDocId: channelDocId,
        body: body,
        authorKind: 'user',
        authorId: 'local-user',
        authorLabel: 'You',
        refs: refs,
      );
      _composerController.clear();
      await _loadMessagesForSelectedChannel();
      widget.onNotify('Message posted');
    } on ApiError catch (error) {
      widget.onNotify(widget.formatApiError(error));
    } finally {
      if (mounted) {
        setState(() {
          _postingMessage = false;
        });
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final hasWorkspace = widget.workspaceId != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hasWorkspace)
            const Expanded(
              child: Center(
                child: Text('Select a workspace to view activity.'),
              ),
            )
          else ...[
            if (_channelsLoading && _channels.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: LinearProgressIndicator(),
              ),
            if (_channels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: KeyedSubtree(
                        key: ValueKey<String>(
                          'activity-channel-dropdown-${_selectedChannelDocId ?? _channels.first.docId}',
                        ),
                        child: DropdownButtonFormField<String>(
                          key: const Key('activity-channel-dropdown'),
                          initialValue:
                              _selectedChannelDocId != null &&
                                  _channels.any(
                                    (item) => item.docId == _selectedChannelDocId,
                                  )
                              ? _selectedChannelDocId
                              : _channels.first.docId,
                          decoration: const InputDecoration(
                            labelText: 'Channel',
                            border: OutlineInputBorder(),
                          ),
                          items: _channels
                              .map(
                                (item) => DropdownMenuItem<String>(
                                  value: item.docId,
                                  child: Text(
                                    item.name.isEmpty
                                        ? '(untitled channel)'
                                        : item.name,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            unawaited(_onChannelSelected(value));
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      key: const Key('activity-channel-actions-button'),
                      onSelected: (value) {
                        unawaited(_handleChannelMenuAction(value));
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'create',
                          child: Text('Create channel'),
                        ),
                        PopupMenuItem<String>(
                          value: 'rename',
                          child: Text('Rename channel'),
                        ),
                        PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('Delete channel'),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.more_vert),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildChatListContent()),
          ],
        ],
      ),
    );
  }

  Widget _buildChatListContent() {
    if (widget.workspaceId == null) {
      return const Center(child: Text('Select a workspace to view chat.'));
    }
    if (_channelsError != null && _channels.isEmpty) {
      return _ActivityErrorState(
        title: 'Channels error',
        message: _channelsError!,
        onRetry: _ensureLoaded,
      );
    }
    if (_channels.isEmpty) {
      return RefreshIndicator(
        onRefresh: _ensureLoaded,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          children: const [
            Center(
              child: Text(
                'No channels yet. Create a channel to start chatting.',
              ),
            ),
          ],
        ),
      );
    }
    if (_messagesLoading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messagesError != null && _messages.isEmpty) {
      return _ActivityErrorState(
        title: 'Messages error',
        message: _messagesError!,
        onRetry: _loadMessagesForSelectedChannel,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMessagesForSelectedChannel,
      child: ListView.separated(
        key: const Key('activity-message-list'),
        controller: _messagesScrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _messages.isEmpty ? 2 : _messages.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (_messages.isEmpty) {
            if (index == 0) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No messages yet in this channel. Post a message.',
                  ),
                ),
              );
            }
            return _InlineComposer(
              controller: _composerController,
              enabled: !_postingMessage,
              onSubmitted: _submitInlineMessage,
            );
          }

          if (index < _messages.length) {
            final item = _messages[index];
            return _ActivityMessageCard(
              message: item,
              friendlyDate: _friendlyDate,
            );
          }

          return _InlineComposer(
            controller: _composerController,
            enabled: !_postingMessage,
            onSubmitted: _submitInlineMessage,
          );
        },
      ),
    );
  }
}

class _ActivityMessageCard extends StatelessWidget {
  const _ActivityMessageCard({
    required this.message,
    required this.friendlyDate,
  });

  final MessageListItem message;
  final String Function(String raw) friendlyDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                friendlyDate(message.createdAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(message.body),
            if (message.refs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: message.refs
                    .map(
                      (ref) => _ActivityPill(
                        label: _activityRefLabel(ref),
                        color: scheme.surfaceContainerHighest,
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}



class _InlineComposer extends StatelessWidget {
  const _InlineComposer({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('activity-inline-message-box'),
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmitted(),
                decoration: const InputDecoration(
                  hintText: 'Write a message...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('activity-inline-send-button'),
              onPressed: enabled ? onSubmitted : null,
              icon: const Icon(Icons.send),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityErrorState extends StatelessWidget {
  const _ActivityErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ErrorBanner(
              title: title,
              message: message,
              copyText: 'title: $title\nmessage: $message',
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ActivityPill extends StatelessWidget {
  const _ActivityPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

String _friendlyDate(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  final local = parsed.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

String _activityRefLabel(CollaborationRef ref) {
  return switch (ref.kind) {
    'user' => '@${ref.displayLabel}',
    'agent' => 'agent:${ref.displayLabel}',
    'flow' => 'flow:${ref.displayLabel}',
    'processor' => 'processor:${ref.displayLabel}',
    'channel' => '#${ref.displayLabel}',
    _ => '${ref.kind}:${ref.displayLabel}',
  };
}
