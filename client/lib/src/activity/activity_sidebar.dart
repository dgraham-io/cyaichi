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

  bool _tasksLoading = false;
  String? _tasksError;
  List<TaskListItem> _tasks = const <TaskListItem>[];

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      unawaited(_ensureLoaded());
    }
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
    _tasksLoading = false;
    _tasksError = null;
    _tasks = const <TaskListItem>[];
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
      if (_tasks.isEmpty && !_tasksLoading) {
        await _loadTasks();
      }
      return;
    }

    await _loadChannels();
    await _loadTasks();
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

  Future<void> _loadTasks() async {
    final workspaceId = widget.workspaceId;
    if (workspaceId == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tasksLoading = false;
        _tasksError = null;
        _tasks = const <TaskListItem>[];
      });
      return;
    }

    if (mounted) {
      setState(() {
        _tasksLoading = true;
        _tasksError = null;
      });
    }

    try {
      final tasks = await widget.apiClient.getTasks(workspaceId: workspaceId);
      if (!mounted) {
        return;
      }
      setState(() {
        _tasks = tasks;
      });
    } on ApiError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tasksError = widget.formatApiError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _tasksLoading = false;
        });
      }
    }
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

  Future<CollaborationRef?> _showAddCustomReferenceDialog() async {
    var kind = 'user';
    final idController = TextEditingController();
    final labelController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Reference'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      decoration: const InputDecoration(
                        labelText: 'Reference kind',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'user', child: Text('user')),
                        DropdownMenuItem(value: 'agent', child: Text('agent')),
                        DropdownMenuItem(value: 'topic', child: Text('topic')),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          kind = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: idController,
                      decoration: const InputDecoration(
                        labelText: 'ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(
                        labelText: 'Label (optional)',
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
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
    final id = idController.text.trim();
    final label = labelController.text.trim();
    idController.dispose();
    labelController.dispose();
    if (submitted != true || id.isEmpty) {
      return null;
    }
    return CollaborationRef(kind: kind, id: id, label: label);
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
    var kind = 'workspace';

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
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      decoration: const InputDecoration(
                        labelText: 'Kind',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'workspace',
                          child: Text('workspace'),
                        ),
                        DropdownMenuItem(value: 'flow', child: Text('flow')),
                        DropdownMenuItem(value: 'topic', child: Text('topic')),
                        DropdownMenuItem(value: 'dm', child: Text('dm')),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          kind = value;
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

    final currentFlowRef = widget.currentFlowRef;
    if (kind == 'flow' && currentFlowRef == null) {
      widget.onNotify('Open or save a flow before creating a flow channel.');
      return;
    }

    try {
      final created = await widget.apiClient.createChannel(
        workspaceId: workspaceId,
        scope: scope,
        name: name,
        kind: kind,
        topic: topic,
        flowDocId: kind == 'flow' ? currentFlowRef?.docId : null,
        flowVerId: kind == 'flow' ? currentFlowRef?.verId : null,
        flowTitle: kind == 'flow' ? currentFlowRef?.displayLabel : null,
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

  Future<void> _showCreateMessageDialog() async {
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

    final selectedChannel = _selectedChannel();
    final bodyController = TextEditingController();
    final authorLabelController = TextEditingController(text: 'You');
    var scope = selectedChannel?.scope ?? 'team';
    var authorKind = 'user';
    final refs = <CollaborationRef>[];

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Post Message'),
              content: SizedBox(
                width: 620,
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
                    DropdownButtonFormField<String>(
                      initialValue: authorKind,
                      decoration: const InputDecoration(
                        labelText: 'Author kind',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'user', child: Text('user')),
                        DropdownMenuItem(value: 'agent', child: Text('agent')),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          authorKind = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: authorLabelController,
                      decoration: const InputDecoration(
                        labelText: 'Author label',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bodyController,
                      minLines: 5,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            final ref = widget.currentFlowRef;
                            if (ref == null || _hasSameRef(refs, ref)) {
                              return;
                            }
                            setDialogState(() {
                              refs.add(ref);
                            });
                          },
                          icon: const Icon(Icons.account_tree_outlined),
                          label: const Text('Ref current flow'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            final ref = widget.selectedProcessorRef;
                            if (ref == null || _hasSameRef(refs, ref)) {
                              return;
                            }
                            setDialogState(() {
                              refs.add(ref);
                            });
                          },
                          icon: const Icon(Icons.memory_outlined),
                          label: const Text('Ref processor'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final ref = await _showAddCustomReferenceDialog();
                            if (ref == null || !context.mounted) {
                              return;
                            }
                            setDialogState(() {
                              if (!_hasSameRef(refs, ref)) {
                                refs.add(ref);
                              }
                            });
                          },
                          icon: const Icon(Icons.alternate_email_outlined),
                          label: const Text('Custom ref'),
                        ),
                      ],
                    ),
                    if (refs.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _RefWrap(
                        refs: refs,
                        onDeleted: (ref) {
                          setDialogState(() {
                            refs.remove(ref);
                          });
                        },
                      ),
                    ],
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
                  child: const Text('Post'),
                ),
              ],
            );
          },
        );
      },
    );

    final body = bodyController.text.trim();
    final authorLabel = authorLabelController.text.trim();
    bodyController.dispose();
    authorLabelController.dispose();
    if (submitted != true) {
      return;
    }
    if (body.isEmpty) {
      widget.onNotify('Message body cannot be empty');
      return;
    }

    try {
      await widget.apiClient.createMessage(
        workspaceId: workspaceId,
        scope: scope,
        channelDocId: channelDocId,
        body: body,
        authorKind: authorKind,
        authorId: _normalizeRefId(authorLabel),
        authorLabel: authorLabel.isEmpty ? 'You' : authorLabel,
        refs: refs,
      );
      await _loadMessagesForSelectedChannel();
      widget.onNotify('Message posted');
    } on ApiError catch (error) {
      widget.onNotify(widget.formatApiError(error));
    }
  }

  Future<void> _showCreateTaskDialog() async {
    final workspaceId = widget.workspaceId;
    if (workspaceId == null) {
      widget.onNotify('Select or create a workspace first.');
      return;
    }

    final selectedChannel = _selectedChannel();
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    final assigneeLabelController = TextEditingController();
    var scope = selectedChannel?.scope ?? 'team';
    var status = 'open';
    var assigneeKind = 'agent';
    final refs = <CollaborationRef>[];

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('New Task'),
              content: SizedBox(
                width: 620,
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
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'open', child: Text('open')),
                        DropdownMenuItem(
                          value: 'in_progress',
                          child: Text('in_progress'),
                        ),
                        DropdownMenuItem(value: 'done', child: Text('done')),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          status = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bodyController,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Body',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: assigneeKind,
                      decoration: const InputDecoration(
                        labelText: 'Assignee kind',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'agent', child: Text('agent')),
                        DropdownMenuItem(value: 'user', child: Text('user')),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          assigneeKind = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: assigneeLabelController,
                      decoration: const InputDecoration(
                        labelText: 'Assignee label (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            final ref = widget.currentFlowRef;
                            if (ref == null || _hasSameRef(refs, ref)) {
                              return;
                            }
                            setDialogState(() {
                              refs.add(ref);
                            });
                          },
                          icon: const Icon(Icons.account_tree_outlined),
                          label: const Text('Ref current flow'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            final ref = widget.selectedProcessorRef;
                            if (ref == null || _hasSameRef(refs, ref)) {
                              return;
                            }
                            setDialogState(() {
                              refs.add(ref);
                            });
                          },
                          icon: const Icon(Icons.memory_outlined),
                          label: const Text('Ref processor'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final ref = await _showAddCustomReferenceDialog();
                            if (ref == null || !context.mounted) {
                              return;
                            }
                            setDialogState(() {
                              if (!_hasSameRef(refs, ref)) {
                                refs.add(ref);
                              }
                            });
                          },
                          icon: const Icon(Icons.add_link_outlined),
                          label: const Text('Custom ref'),
                        ),
                      ],
                    ),
                    if (refs.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _RefWrap(
                        refs: refs,
                        onDeleted: (ref) {
                          setDialogState(() {
                            refs.remove(ref);
                          });
                        },
                      ),
                    ],
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

    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    final assigneeLabel = assigneeLabelController.text.trim();
    titleController.dispose();
    bodyController.dispose();
    assigneeLabelController.dispose();
    if (submitted != true) {
      return;
    }
    if (title.isEmpty) {
      widget.onNotify('Task title cannot be empty');
      return;
    }

    try {
      await widget.apiClient.createTask(
        workspaceId: workspaceId,
        scope: scope,
        title: title,
        body: body,
        status: status,
        channelDocId: _selectedChannelDocId,
        assigneeKind: assigneeLabel.isEmpty ? '' : assigneeKind,
        assigneeId: assigneeLabel.isEmpty ? '' : _normalizeRefId(assigneeLabel),
        assigneeLabel: assigneeLabel,
        refs: refs,
      );
      await _loadTasks();
      widget.onNotify('Task created');
    } on ApiError catch (error) {
      widget.onNotify(widget.formatApiError(error));
    }
  }

  Future<void> _updateTaskStatus(TaskListItem item, String status) async {
    try {
      await widget.apiClient.patchTaskStatus(
        taskDocId: item.docId,
        status: status,
      );
      await _loadTasks();
      widget.onNotify('Task updated');
    } on ApiError catch (error) {
      widget.onNotify(widget.formatApiError(error));
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const Key('sidebar-activity-new-channel-button'),
                onPressed: hasWorkspace ? _showCreateChannelDialog : null,
                icon: const Icon(Icons.forum_outlined),
                label: const Text('New channel'),
              ),
              FilledButton.tonalIcon(
                key: const Key('sidebar-activity-new-message-button'),
                onPressed: hasWorkspace ? _showCreateMessageDialog : null,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Post'),
              ),
              FilledButton.tonalIcon(
                key: const Key('sidebar-activity-new-task-button'),
                onPressed: hasWorkspace ? _showCreateTaskDialog : null,
                icon: const Icon(Icons.task_alt_outlined),
                label: const Text('New task'),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      onTap: (index) {
                        if (index == 0) {
                          unawaited(_loadMessagesForSelectedChannel());
                        } else {
                          unawaited(_loadTasks());
                        }
                      },
                      tabs: const [
                        Tab(
                          key: Key('activity-chat-tab-button'),
                          icon: Icon(Icons.chat_outlined),
                          text: 'Chat',
                        ),
                        Tab(
                          key: Key('activity-tasks-tab-button'),
                          icon: Icon(Icons.checklist_outlined),
                          text: 'Tasks',
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: TabBarView(
                        children: [
                          KeyedSubtree(
                            key: const Key('activity_chat_tab'),
                            child: _buildChatListContent(),
                          ),
                          KeyedSubtree(
                            key: const Key('activity_tasks_tab'),
                            child: _buildTaskListContent(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
      child: _messages.isEmpty
          ? ListView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              children: const [
                Center(
                  child: Text(
                    'No messages yet in this channel. Post a message.',
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = _messages[index];
                return _ActivityMessageCard(
                  message: item,
                  friendlyDate: _friendlyDate,
                );
              },
            ),
    );
  }

  Widget _buildTaskListContent() {
    if (widget.workspaceId == null) {
      return const Center(child: Text('Select a workspace to view tasks.'));
    }
    if (_tasksLoading && _tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tasksError != null && _tasks.isEmpty) {
      return _ActivityErrorState(
        title: 'Tasks error',
        message: _tasksError!,
        onRetry: _loadTasks,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: _tasks.isEmpty
          ? ListView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              children: const [
                Center(child: Text('No tasks yet for this workspace.')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = _tasks[index];
                return _ActivityTaskCard(
                  task: item,
                  friendlyDate: _friendlyDate,
                  onStatusChanged: (status) => _updateTaskStatus(item, status),
                );
              },
            ),
    );
  }
}

class _RefWrap extends StatelessWidget {
  const _RefWrap({required this.refs, this.onDeleted});

  final List<CollaborationRef> refs;
  final ValueChanged<CollaborationRef>? onDeleted;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: refs
          .map(
            (ref) => InputChip(
              label: Text(_activityRefLabel(ref)),
              onDeleted: onDeleted == null ? null : () => onDeleted!(ref),
            ),
          )
          .toList(growable: false),
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
    final authorLabel = message.authorLabel.trim().isEmpty
        ? (message.authorId.trim().isEmpty ? '(unknown)' : message.authorId)
        : message.authorLabel;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  authorLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                _ActivityPill(
                  label: message.authorKind,
                  color: scheme.surfaceContainerHighest,
                ),
              ],
            ),
            const SizedBox(height: 4),
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

class _ActivityTaskCard extends StatelessWidget {
  const _ActivityTaskCard({
    required this.task,
    required this.friendlyDate,
    required this.onStatusChanged,
  });

  final TaskListItem task;
  final String Function(String raw) friendlyDate;
  final ValueChanged<String> onStatusChanged;

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title.trim().isEmpty
                            ? '(untitled task)'
                            : task.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${friendlyDate(task.createdAt)} • ${task.scope}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: task.status,
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('open')),
                      DropdownMenuItem(
                        value: 'in_progress',
                        child: Text('in_progress'),
                      ),
                      DropdownMenuItem(value: 'done', child: Text('done')),
                    ],
                    onChanged: (value) {
                      if (value == null || value == task.status) {
                        return;
                      }
                      onStatusChanged(value);
                    },
                  ),
                ),
              ],
            ),
            if (task.assigneeLabel.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _ActivityPill(
                label: 'assignee:${task.assigneeLabel}',
                color: scheme.surfaceContainerHighest,
              ),
            ],
            if (task.bodyPreview.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(task.bodyPreview),
            ],
            if (task.refs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: task.refs
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

String _normalizeRefId(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(' ', '_');
  return normalized.isEmpty ? 'local-user' : normalized;
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
    'task' => 'task:${ref.displayLabel}',
    'channel' => '#${ref.displayLabel}',
    _ => '${ref.kind}:${ref.displayLabel}',
  };
}
