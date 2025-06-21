import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- Added for input formatter
import '../services/wb_police_scraper_service.dart';

class ContactSearchScreen extends StatefulWidget {
  const ContactSearchScreen({super.key});

  @override
  State<ContactSearchScreen> createState() => _ContactSearchScreenState();
}

class _ContactSearchScreenState extends State<ContactSearchScreen> {
  final WBPoliceScraperService _scraper = WBPoliceScraperService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isLoading = false;
  bool _isInitializing = false;
  String _searchResult = '';
  Map<String, String>? _foundContact;

  @override
  void initState() {
    super.initState();
    _checkAndInitializeDatabaseOnStartup();
  }

  Future<void> _checkAndInitializeDatabaseOnStartup() async {
    setState(() => _isInitializing = true);
    try {
      final existingContacts = await _scraper.searchContact("");

      if (existingContacts == null || existingContacts.isEmpty) {
        print('Contact database file not found or is empty. Initializing...');
        await _initializeDatabase(initialRun: true);
      } else {
        print(
          'Contact database file found and contains data. Skipping initial scraping.',
        );
        setState(() {
          _searchResult = 'Database loaded, ready to search!';
        });
      }
    } catch (e) {
      print('Error during initial database check: $e');
      setState(() {
        _searchResult = 'Error loading database: $e';
      });
    } finally {
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _initializeDatabase({bool initialRun = false}) async {
    setState(() => _isInitializing = true);
    String message = initialRun
        ? 'Initializing contact database for the first time...'
        : 'Refreshing contact database...';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    try {
      await _scraper.fetchAndStoreContacts();
      setState(() {
        _searchResult = 'Database initialized successfully!';
        _foundContact = null;
        _searchController.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Database updated!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize database: $e')),
      );
      setState(() {
        _searchResult = 'Initialization failed: $e';
      });
    } finally {
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _searchContact() async {
    final phoneNumber = _searchController.text.trim();
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a phone number to search.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _searchResult = '';
      _foundContact = null;
    });

    try {
      final contact = await _scraper.searchContact(phoneNumber);

      setState(() {
        _foundContact = contact;
        _searchResult = (contact != null && contact.isNotEmpty)
            ? 'Match found!'
            : 'No match found in database';
      });
    } catch (e) {
      setState(() {
        _searchResult = 'Search error: $e';
      });
    } finally {
      setState(() => _isLoading = false);
      _searchFocusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Number Checker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading || _isInitializing
                ? null
                : () => _initializeDatabase(initialRun: false),
            tooltip: 'Refresh Database',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_isInitializing) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'Checking database or Initializing... Please wait, this may take a moment.',
              ),
              const SizedBox(height: 32),
            ],
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                labelText: 'Enter phone number',
                hintText: 'e.g. 9876543210',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _isLoading || _isInitializing
                      ? null
                      : _searchContact,
                ),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) =>
                  _isLoading || _isInitializing ? null : _searchContact(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading || _isInitializing
                    ? null
                    : _searchContact,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Search Contact'),
              ),
            ),
            const SizedBox(height: 20),
            if (_searchResult.isNotEmpty) ...[
              Text(
                _searchResult,
                style: TextStyle(
                  fontSize: 18,
                  color: (_foundContact != null && _foundContact!.isNotEmpty)
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
              if (_foundContact != null && _foundContact!.isNotEmpty) ...[
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Name: ${_foundContact!['name']}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          'Designation: ${_foundContact!['designation']}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          'Phone: ${_foundContact!['phone']}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
}
