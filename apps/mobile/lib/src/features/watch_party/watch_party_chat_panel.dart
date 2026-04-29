import 'package:awatv_mobile/src/features/watch_party/watch_party_state.dart';
import 'package:awatv_mobile/src/shared/remote/watch_party_protocol.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// Right-side panel showing party-chat messages plus an input field.
/// In wide layouts the player widget pushes this to the right gutter;
/// in narrow layouts it overlays the bottom of the screen.
class WatchPartyChatPanel extends StatefulWidget {
  const WatchPartyChatPanel({
    required this.state,
    required this.onSend,
    super.key,
  });

  final WatchPartyState state;
  final Future<void> Function(String message) onSend;

  @override
  State<WatchPartyChatPanel> createState() => _WatchPartyChatPanelState();
}

class _WatchPartyChatPanelState extends State<WatchPartyChatPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(WatchPartyChatPanel old) {
    super.didUpdateWidget(old);
    // Auto-scroll to bottom when a new message lands.
    if (widget.state.chat.length != old.state.chat.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    await widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          left: BorderSide(
            color: scheme.outline.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
              vertical: DesignTokens.spaceS,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.chat_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: DesignTokens.spaceS),
                Text(
                  'Sohbet',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.state.chat.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 0),
          Expanded(
            child: widget.state.chat.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(DesignTokens.spaceL),
                      child: Text(
                        'Henuz mesaj yok. Ilki sen yaz!',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spaceM,
                      vertical: DesignTokens.spaceS,
                    ),
                    separatorBuilder: (BuildContext _, int __) =>
                        const SizedBox(height: 6),
                    itemCount: widget.state.chat.length,
                    itemBuilder: (BuildContext _, int i) {
                      final m = widget.state.chat[i];
                      final isOwn = m.isOwn(widget.state.localUserId);
                      return _ChatBubble(
                        message: m,
                        isOwn: isOwn,
                      );
                    },
                  ),
          ),
          const Divider(height: 0),
          Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceS),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yaz...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (String _) => _onSubmit(),
                  ),
                ),
                IconButton(
                  tooltip: 'Gonder',
                  icon: const Icon(Icons.send_rounded),
                  onPressed: _onSubmit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.isOwn});

  final PartyChat message;
  final bool isOwn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isOwn
            ? scheme.primary.withValues(alpha: 0.18)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
      ),
      child: Column(
        crossAxisAlignment:
            isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            message.userName,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
          Text(
            message.message,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: bubble,
      ),
    );
  }
}
