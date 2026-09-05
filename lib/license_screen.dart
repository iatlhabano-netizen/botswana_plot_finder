import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'license_service.dart';

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});
  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _codeCtrl = TextEditingController();
  LicenseInfo? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() { _codeCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final info = await LicenseService.load();
    setState(() { _info = info; _loading = false; });
  }

  Future<void> _activate() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    final msg = await LicenseService.activateWithCode(code);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    _codeCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final tier = _info?.tier ?? LicenseTier.free;
    final isActive = _info?.isActive ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('License & Activation', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0070BA),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Current status
                Card(
                  color: isActive
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(isActive ? Icons.verified : Icons.lock_open, color: isActive ? Colors.green : Colors.grey, size: 28),
                        const SizedBox(width: 10),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tier.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          Text(
                            isActive
                                ? (tier == LicenseTier.free
                                    ? 'Free tier — basic features only'
                                    : 'Active until ${_info!.expiresAt != null ? '${_info!.expiresAt!.day}/${_info!.expiresAt!.month}/${_info!.expiresAt!.year}' : 'permanent'}')
                                : 'No active license',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          ),
                        ]),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),

                // Activation code entry
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Enter Activation Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Format: FU-AB12-CD34 (Field Unlock) or CP-EF56-GH78 (Contractor Pro)',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _codeCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'FU-XXXX-XXXX',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => _codeCtrl.clear()),
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
                              LengthLimitingTextInputFormatter(15),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0070BA)),
                          onPressed: _activate,
                          icon: const Icon(Icons.key, color: Colors.white),
                          label: const Text('Activate', style: TextStyle(color: Colors.white)),
                        ),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 24),

                // Tier comparison
                const Text('What you get with each tier:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                _tierCard(
                  name: 'Free',
                  price: 'Free forever',
                  features: [
                    'Lo to WGS84 coordinate conversion',
                    'Pin viewing on the map',
                    'Basic area calculation (m² and hectares)',
                    'Plot boundary display',
                  ],
                  unlocked: true,
                ),
                const SizedBox(height: 12),

                _tierCard(
                  name: 'Field Unlock',
                  price: 'BWP 75 – 100 (one-time, permanent)',
                  features: [
                    'Certificate OCR scanner (camera + gallery)',
                    'Bush navigation (line-following for pipes/fences)',
                    'PDF audit report with map preview',
                    'Export to KML, GPX, CSV, JSON',
                    'Area verification against certificate',
                    'Multi-plot management',
                  ],
                  unlocked: tier.level >= LicenseTier.fieldUnlock.level && isActive,
                ),
                const SizedBox(height: 12),

                _tierCard(
                  name: 'Contractor Pro',
                  price: 'BWP 2,500 / year',
                  features: [
                    'Everything in Field Unlock',
                    'Unlimited point-to-point line tracking',
                    'Multi-plot client management (50+ farms)',
                    'White-label PDF reports (your logo & phone)',
                    'Priority WhatsApp support',
                    '6-month & annual plans available',
                  ],
                  unlocked: tier.level >= LicenseTier.contractorPro.level && isActive,
                ),
                const SizedBox(height: 24),

                // How to buy
                Card(
                  color: Colors.blue.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('How to activate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('1. Pay via Orange Money, SmartEC, or eWallet', style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text('2. Send proof of payment to our WhatsApp', style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text('3. Receive your activation code instantly', style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text('4. Enter the code above to unlock', style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                          onPressed: () => launchUrl(Uri.parse('https://wa.me/26775388737?text=Hi%2C%20I%20want%20to%20buy%20a%20Plot%20Finder%20license')),
                          icon: const Icon(Icons.chat, color: Colors.white),
                          label: const Text('Request license via WhatsApp', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
              ]),
            ),
    );
  }

  Widget _tierCard({required String name, required String price, required List<String> features, required bool unlocked}) {
    return Card(
      elevation: unlocked ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: unlocked ? const Color(0xFF0070BA) : Colors.grey.shade300, width: unlocked ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (unlocked) const Icon(Icons.check_circle, color: Color(0xFF0070BA)),
          ]),
          Text(price, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Icon(Icons.check, size: 16, color: unlocked ? const Color(0xFF0070BA) : Colors.grey),
              const SizedBox(width: 8),
              Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
            ]),
          )),
        ]),
      ),
    );
  }
}
