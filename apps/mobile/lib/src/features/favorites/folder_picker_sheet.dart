import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/favorites/favorites_providers.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom sheet that lets the user pick which folder a [channelId]
/// should live in. Returns the chosen folder id when the sheet
/// dismisses, or null when the user backed out.
class FolderPickerSheet extends ConsumerStatefulWidget {
  const FolderPickerSheet({required this.channelId, super.key});

  final String channelId;

  static Future<String?> show(
    BuildContext context, {
    required String channelId,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext _) => FolderPickerSheet(channelId: channelId),
    );
  }

  @override
  ConsumerState<FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends ConsumerState<FolderPickerSheet> {
  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(favoriteFoldersStreamProvider);
    return SafeArea(
      child: foldersAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(DesignTokens.spaceL),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (Object e, StackTrace _) => Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceL),
          child: Text('Klasorler yuklenemedi: $e'),
        ),
        data: (List<FavoriteFolder> folders) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(
                title: Text(
                  'Klasor sec',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Divider(height: 0),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final f in folders)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: f.color != null
                              ? Color(f.color!)
                              : Theme.of(context).colorScheme.primary,
                          child: const Icon(
                            Icons.folder_rounded,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(f.name),
                        subtitle: Text('${f.channelIds.length} kanal'),
                        trailing: f.channelIds.contains(widget.channelId)
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.of(context).pop(f.id),
                      ),
                  ],
                ),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Yeni klasor'),
                onTap: () async {
                  final name = await _prompt(context);
                  if (name == null || name.trim().isEmpty) return;
                  final svc = ref.read(favoritesServiceProvider);
                  final folder = await svc.createFolder(name: name);
                  if (mounted) Navigator.of(context).pop(folder.id);
                },
              ),
              const SizedBox(height: DesignTokens.spaceM),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _prompt(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Yeni klasor'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Klasor adi',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (String v) => Navigator.of(ctx).pop(v),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Iptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Olustur'),
            ),
          ],
        );
      },
    );
  }
}
