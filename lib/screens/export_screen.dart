import 'package:flutter/material.dart';
import '../services/export_service.dart';

class ExportScreen extends StatefulWidget {
  final String orgId;
  final String orgName;

  const ExportScreen({
    super.key,
    required this.orgId,
    required this.orgName,
  });

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  _Format _format = _Format.excel;
  bool _isGenerating = false;
  String? _errorMessage;

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final first = isFrom ? DateTime(2020) : _from;
    final last = isFrom ? _to : DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _generate() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final receipts = await ExportService.fetchReceipts(
        orgId: widget.orgId,
        from: _from,
        to: _to,
      );

      if (receipts.isEmpty) {
        setState(() => _errorMessage =
            'No receipts found between ${_fmt(_from)} and ${_fmt(_to)}.');
        return;
      }

      final file = _format == _Format.excel
          ? await ExportService.exportExcel(
              orgName: widget.orgName,
              from: _from,
              to: _to,
              receipts: receipts,
            )
          : await ExportService.exportPdf(
              orgName: widget.orgName,
              from: _from,
              to: _to,
              receipts: receipts,
            );

      await ExportService.shareFile(file);
    } catch (e) {
      setState(() => _errorMessage = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Receipts')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date range
            const Text('Date Range',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateTile(
                    label: 'From',
                    date: _from,
                    onTap: () => _pickDate(isFrom: true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('→', style: TextStyle(fontSize: 18)),
                ),
                Expanded(
                  child: _DateTile(
                    label: 'To',
                    date: _to,
                    onTap: () => _pickDate(isFrom: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Format selector
            const Text('Format',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _FormatCard(
                    icon: Icons.table_chart_outlined,
                    label: 'Excel',
                    subtitle: 'Summary + line items\nas separate sheets',
                    selected: _format == _Format.excel,
                    onTap: () => setState(() => _format = _Format.excel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FormatCard(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'PDF',
                    subtitle: 'Printable report\nwith tables',
                    selected: _format == _Format.pdf,
                    onTap: () => setState(() => _format = _Format.pdf),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Quick range shortcuts
            const Text('Quick Select',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                _QuickChip(
                  label: 'Last 7 days',
                  onTap: () => setState(() {
                    _to = DateTime.now();
                    _from = _to.subtract(const Duration(days: 7));
                  }),
                ),
                _QuickChip(
                  label: 'Last 30 days',
                  onTap: () => setState(() {
                    _to = DateTime.now();
                    _from = _to.subtract(const Duration(days: 30));
                  }),
                ),
                _QuickChip(
                  label: 'This month',
                  onTap: () => setState(() {
                    final now = DateTime.now();
                    _from = DateTime(now.year, now.month, 1);
                    _to = now;
                  }),
                ),
                _QuickChip(
                  label: 'Last month',
                  onTap: () => setState(() {
                    final now = DateTime.now();
                    final firstOfThisMonth = DateTime(now.year, now.month, 1);
                    _to = firstOfThisMonth.subtract(const Duration(days: 1));
                    _from = DateTime(_to.year, _to.month, 1);
                  }),
                ),
              ],
            ),

            const SizedBox(height: 32),

            if (_errorMessage != null) ...[
              Text(_errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
              const SizedBox(height: 12),
            ],

            FilledButton.icon(
              onPressed: _isGenerating ? null : _generate,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download),
              label: Text(_isGenerating ? 'Generating...' : 'Generate & Share'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'File will be saved and the share sheet will open.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Format { excel, pdf }

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DateTile({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final formatted =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 14),
                const SizedBox(width: 6),
                Text(formatted,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _FormatCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
          color: selected ? color.withOpacity(0.05) : null,
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: selected ? color : Colors.grey),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? color : null)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}