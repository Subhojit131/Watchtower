import 'package:flutter/material.dart';
import '../services/url_checker_service.dart';

class ScanLinkPage extends StatefulWidget {
  const ScanLinkPage({super.key});

  @override
  State<ScanLinkPage> createState() => _ScanLinkPageState();
}

class _ScanLinkPageState extends State<ScanLinkPage> {
  final _urlController = TextEditingController();
  String? result;
  bool isSafe = true;

  void scanLink() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      result = "⏳ Scanning...";
    });

    try {
      final isUnsafe = await UrlCheckerService.checkWithGoogleSafeBrowsing(url);
      setState(() {
        result = isUnsafe ? "⚠️ Unsafe Link Detected!" : "✅ Link Looks Safe.";
        isSafe = !isUnsafe;
      });
    } catch (e) {
      setState(() {
        result = "❌ Error checking URL. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Link")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: "Enter URL",
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: scanLink,
              icon: const Icon(Icons.shield),
              label: const Text("Scan now"),
            ),
            const SizedBox(height: 20),
            if (result != null)
              Text(
                result!,
                style: TextStyle(
                  color: isSafe ? Colors.green : Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
