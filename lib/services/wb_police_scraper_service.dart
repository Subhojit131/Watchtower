import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart'; // Import for Element
import 'package:path_provider/path_provider.dart';

class WBPoliceScraperService {
  // Base URL of the contact list page
  static const String baseUrl =
      "https://wbpolice.gov.in/wbp/Common/WBP_ContactList.aspx";
  // File name for storing scraped contacts locally
  static const String contactsFileName = 'wb_police_contacts.json';

  // Common headers to make requests appear more like a web browser
  static const Map<String, String> defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
    'Accept-Language': 'en-US,en;q=0.9',
    'Connection': 'keep-alive',
  };

  // Field to store cookies obtained from previous responses
  String? _sessionCookie;

  /// Main method to fetch contacts from the website and store them locally.
  /// This will overwrite any existing local contacts.
  Future<void> fetchAndStoreContacts() async {
    print('Starting fetchAndStoreContacts...');
    final contacts = await _scrapeAllContacts();
    print('Scraped ${contacts.length} contacts.');
    if (contacts.isNotEmpty) {
      await _saveContactsToFile(contacts);
    } else {
      print('No contacts scraped. Not saving an empty file.');
    }
    print('Finished fetchAndStoreContacts.');
  }

  /// Searches for a contact by phone number in the locally stored contacts.
  /// Returns a map of contact details if found, otherwise an empty map.
  Future<Map<String, String>?> searchContact(String phoneNumber) async {
    print('Searching for contact: $phoneNumber');
    final contacts = await _loadContactsFromFile();
    print('Loaded ${contacts.length} contacts from file for search.');
    // Normalize the input phone number and compare with normalized stored numbers
    return contacts.firstWhere(
      (c) => _normalizePhone(
        c['phone'] ?? '',
      ).contains(_normalizePhone(phoneNumber)),
      orElse: () => {}, // Return an empty map if no contact is found
    );
  }

  /// Normalizes a phone number by removing all non-digit characters.
  String _normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Loads contacts from a local JSON file.
  /// Returns a list of contact maps, or an empty list if an error occurs or file doesn't exist.
  Future<List<Map<String, String>>> _loadContactsFromFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$contactsFileName');
      print('Attempting to load contacts from: ${file.path}');

      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.isEmpty) {
          print('Loaded file is empty.');
          return [];
        }
        final List<dynamic> jsonList = json.decode(contents);
        print('Successfully loaded ${jsonList.length} items from file.');
        // Convert dynamic list to List<Map<String, String>>
        return jsonList.map((item) => Map<String, String>.from(item)).toList();
      } else {
        print('Contact file does not exist at ${file.path}.');
      }
    } catch (e) {
      print('Error loading contacts: $e'); // Log the error
    }
    return []; // Return empty list on error or if file doesn't exist
  }

  /// Saves a list of contacts to a local JSON file.
  /// Throws an error if saving fails.
  Future<void> _saveContactsToFile(List<Map<String, String>> contacts) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$contactsFileName');
      await file.writeAsString(json.encode(contacts));
      print('Contacts saved to ${file.path}'); // Confirm save
    } catch (e) {
      print('Error saving contacts: $e'); // Log the error
      rethrow; // Re-throw to propagate the error
    }
  }

  /// Scrapes all pages of contacts from the website.
  /// This method now handles fetching the initial page and its view state,
  /// then iteratively scrapes subsequent pages by simulating numerical page clicks.
  Future<List<Map<String, String>>> _scrapeAllContacts() async {
    List<Map<String, String>> allContacts = [];
    Map<String, String> currentHiddenFields = {};
    Document? currentDocument;
    int currentPage = 1;

    try {
      // 1. Initial GET request to get the first page and its hidden fields
      print(
        'Performing initial GET request to get page 1 and hidden fields...',
      );
      final initialResponse = await http.get(
        Uri.parse(baseUrl),
        headers: defaultHeaders,
      );

      // Capture cookies from the initial response
      _sessionCookie = initialResponse.headers['set-cookie'];
      if (_sessionCookie != null) {
        print('Captured session cookie: $_sessionCookie');
      }

      if (initialResponse.statusCode != 200) {
        print('Initial GET failed with status: ${initialResponse.statusCode}');
        return [];
      }
      currentDocument = parser.parse(initialResponse.body);
      currentHiddenFields = _getFormHiddenFields(currentDocument);
      print(
        'Successfully obtained initial hidden form fields: ${currentHiddenFields.keys}',
      );

      // Scrape contacts from the first page
      final contactsOnFirstPage = _parseContactsFromPage(currentDocument);
      allContacts.addAll(contactsOnFirstPage);
      print(
        'Scraped ${contactsOnFirstPage.length} contacts from page $currentPage.',
      );

      // Loop to navigate through pages until no more pagination links are found
      while (true) {
        String? nextEventTarget;
        String? nextEventArgument;

        // Try to find the link for the next sequential page number (currentPage + 1)
        Element? nextNavLink;
        final paginationLinks = currentDocument!.querySelectorAll(
          "a[href*='__doPostBack']",
        );
        for (var link in paginationLinks) {
          final argMatch = RegExp(
            r"Page\$(\d+)",
          ).firstMatch(link.attributes['href'] ?? '');
          if (argMatch != null) {
            final pageNum = int.tryParse(argMatch.group(1)!);
            if (pageNum == currentPage + 1) {
              // This is the direct next page link
              nextNavLink = link;
              break;
            }
          }
        }

        if (nextNavLink != null) {
          final href = nextNavLink.attributes['href'];
          if (href != null && href.startsWith('javascript:__doPostBack')) {
            final postbackMatch = RegExp(
              r"__doPostBack\('([^']*)','([^']*)'\)",
            ).firstMatch(href);
            if (postbackMatch != null && postbackMatch.groupCount >= 2) {
              nextEventTarget = postbackMatch.group(1);
              nextEventArgument = postbackMatch.group(2);
              print(
                'Found next page link with __EVENTTARGET: $nextEventTarget, __EVENTARGUMENT: $nextEventArgument',
              );
            } else {
              print('Could not parse __doPostBack from next link href: $href');
              break; // Exit loop if parsing fails
            }
          } else {
            print('Next link href is not a __doPostBack call or is null.');
            break; // Exit loop
          }
        } else {
          print(
            'No valid link found for page ${currentPage + 1}. Assuming end of pages.',
          );
          break; // No more navigation links, so exit the loop
        }

        // If we found valid event target and argument for the next page
        if (nextEventTarget != null && nextEventArgument != null) {
          currentPage++; // Increment page counter for logging
          print('Scraping page $currentPage...');
          await Future.delayed(
            const Duration(seconds: 1),
          ); // Be polite to server

          // Call _fetchPageHtmlAndFields expecting a full HTML response
          final pageData = await _fetchPageHtmlAndFields(
            nextEventTarget,
            nextEventArgument,
            currentHiddenFields,
            baseUrl,
          );
          if (pageData == null) {
            print('Failed to fetch page $currentPage. Stopping scraping.');
            break; // Stop if a page fails to load
          }

          // Parse the full HTML response (no AJAX Delta expected now)
          currentDocument = parser.parse(pageData['htmlBody']!);
          // Re-extract all hidden fields from the newly loaded page
          currentHiddenFields = _getFormHiddenFields(currentDocument);
          print('Parsed full HTML response for page $currentPage.');
          print(
            'Updated hidden fields from full page response: ${currentHiddenFields.keys}',
          );

          final pageContacts = _parseContactsFromPage(currentDocument);
          allContacts.addAll(pageContacts);
          print(
            'Scraped ${pageContacts.length} contacts from page $currentPage. Total contacts: ${allContacts.length}',
          );
        } else {
          break; // Should not happen if nextNavLink was found and parsed
        }
      }
    } catch (e) {
      print('Error scraping all contacts: $e'); // Log the error
      rethrow; // Re-throw to propagate the error
    }
    return allContacts;
  }

  /// Helper to fetch a specific page's HTML and its hidden form fields via POST.
  /// Returns a map containing 'htmlBody' and 'hiddenFields', or null on failure.
  /// This method now takes dynamic eventTarget and eventArgument for pagination.
  Future<Map<String, dynamic>?> _fetchPageHtmlAndFields(
    String eventTarget,
    String eventArgument,
    Map<String, String> previousHiddenFields,
    String refererUrl, // Added refererUrl parameter
  ) async {
    print(
      'Posting to get page with eventTarget: "$eventTarget", eventArgument: "$eventArgument" and hidden fields...',
    );
    try {
      final Map<String, String> postBody = Map.from(previousHiddenFields);
      postBody['__EVENTTARGET'] = eventTarget;
      postBody['__EVENTARGUMENT'] = eventArgument;

      // Merge default headers with referer specific to this request
      final Map<String, String> headers = {
        ...defaultHeaders,
        'Referer': refererUrl, // Set the Referer header
        'Content-Type':
            'application/x-www-form-urlencoded; charset=UTF-8', // Explicitly add charset
        // IMPORTANT: Removed X-MicrosoftAjax header as browser does not send it.
        // This likely caused the server to send an AJAX delta, which we don't expect.
      };

      // Add the session cookie if available
      if (_sessionCookie != null) {
        headers['Cookie'] = _sessionCookie!;
      }

      final response = await http.post(
        Uri.parse(baseUrl),
        body: postBody,
        headers: headers,
      );

      print('POST response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        return {
          'htmlBody': response.body,
          'hiddenFields':
              <
                String,
                String
              >{}, // Not used directly for full HTML response, but kept for consistency
        };
      }
    } catch (e) {
      print('Error fetching page via POST: $e');
    }
    return null;
  }

  /// Parses and extracts contacts from a given HTML Document.
  List<Map<String, String>> _parseContactsFromPage(Document document) {
    List<Map<String, String>> contacts = [];
    // Selector for the main contact table, based on the provided ID snippets
    final table = document.querySelector(
      "#ctl00_ContentPlaceHolder1_grid_contactus",
    );
    if (table != null) {
      print('Table with ID #ctl00_ContentPlaceHolder1_grid_contactus found.');
      final rows = table.querySelectorAll("tr");
      print('Found ${rows.length} rows in the table.');
      // Iterate starting from the second row to skip header (first row is usually headers)
      for (int i = 1; i < rows.length; i++) {
        final cells = rows[i].querySelectorAll("td");
        // Based on the screenshot, there are only 2 data columns.
        // We need at least 2 cells to extract name/office and phone number.
        if (cells.length >= 2) {
          // Extract name/office from the first cell, looking for span with ID ending in 'Label1'
          final nameElement = cells[0].querySelector('span[id\$="Label1"]');
          // Extract phone from the second cell (index 1), looking for span with ID ending in 'Label3'
          final phoneElement = cells[1].querySelector('span[id\$="Label3"]');

          final name = nameElement?.text.trim() ?? '';
          // The "designation" field seems to be part of the "Name of Office/Establishment"
          // in the screenshot, or it's not a distinct column.
          // For simplicity, let's just use the 'name' field for the office/designation.
          final designation =
              name; // Or could be an empty string if not applicable.
          final phone = phoneElement?.text.trim() ?? '';

          if (name.isNotEmpty || phone.isNotEmpty) {
            contacts.add({
              'name': name,
              // 'designation' is derived from 'name' since it's not a separate column in the screenshot.
              'designation': designation,
              'phone': phone,
            });
          } else {
            print(
              'Skipping row $i: Name or Phone span not found or empty after parsing.',
            );
          }
        } else {
          print(
            'Row $i has less than 2 cells (${cells.length}). Skipping.',
          ); // Adjusted log
        }
      }
    } else {
      print(
        'Table with ID #ctl00_ContentPlaceHolder1_grid_contactus NOT found.',
      );
    }
    return contacts;
  }

  /// Extracts common ASP.NET hidden form fields from an HTML document.
  /// It now robustly looks for all hidden inputs within the document's main form.
  Map<String, String> _getFormHiddenFields(Document document) {
    final Map<String, String> hiddenFields = {};
    // Find the main form (assuming there's one)
    final form = document.querySelector('form');
    if (form != null) {
      // Find all hidden input fields within the form
      final hiddenInputs = form.querySelectorAll('input[type="hidden"]');
      for (var input in hiddenInputs) {
        final name = input.attributes['name'];
        final value = input.attributes['value'];
        if (name != null && value != null) {
          hiddenFields[name] = value;
        }
      }
    } else {
      print('Main form element not found. Cannot extract hidden fields.');
    }
    print('Extracted hidden fields: ${hiddenFields.keys}');
    return hiddenFields;
  }

  /// Parses an ASP.NET AJAX Delta response string.
  /// This method is no longer actively used in the main scraping flow
  /// because the browser's behavior indicates a full HTML response is expected.
  /// Keeping it for reference/potential future use if behavior changes.
  Map<String, dynamic> _parseAjaxDeltaResponse(String deltaResponse) {
    print(
      'NOTE: _parseAjaxDeltaResponse is not used in the primary scraping flow.',
    );
    String? updatedHtmlContent;
    final Map<String, String> hiddenFields = {};

    if (!deltaResponse.startsWith('|')) {
      print('Response is not an AJAX Delta. Assuming full HTML response.');
      return {'updatedHtml': null, 'hiddenFields': {}};
    }

    print('Detected AJAX Delta response. Parsing...');
    int currentPos = 1;

    while (currentPos < deltaResponse.length) {
      int nextPipe = deltaResponse.indexOf('|', currentPos);
      if (nextPipe == -1) {
        print(
          'Error: Malformed AJAX Delta response (no pipe found after index $currentPos).',
        );
        break;
      }

      String lengthStr = deltaResponse.substring(currentPos, nextPipe);
      int? segmentLength;
      try {
        segmentLength = int.parse(lengthStr);
      } catch (e) {
        print(
          'Error: Could not parse segment length "$lengthStr" at index $currentPos. Breaking: $e',
        );
        break;
      }

      currentPos = nextPipe + 1;

      int nextTypePipe = deltaResponse.indexOf('|', currentPos);
      if (nextTypePipe == -1) {
        print(
          'Error: Malformed AJAX Delta response (no type pipe found after index $currentPos).',
        );
        break;
      }
      String type = deltaResponse.substring(currentPos, nextTypePipe);
      currentPos = nextTypePipe + 1;

      if (currentPos + segmentLength > deltaResponse.length) {
        print(
          'Error: Segment content length ($segmentLength) exceeds remaining response length. Breaking.',
        );
        break;
      }
      String content = deltaResponse.substring(
        currentPos,
        currentPos + segmentLength,
      );
      currentPos += segmentLength;

      if (currentPos < deltaResponse.length &&
          deltaResponse[currentPos] == '|') {
        currentPos++;
      }

      if (type == 'field' || type == 'hiddenField') {
        final fieldParts = content.split('|');
        if (fieldParts.length >= 2) {
          final fieldName = fieldParts[0];
          final fieldValue = fieldParts[1];
          hiddenFields[fieldName] = fieldValue;
          print('  AJAX Delta: Extracted field "$fieldName": "$fieldValue"');
        } else {
          print('  AJAX Delta: Unexpected field content format: "$content"');
        }
      } else if (type == 'updatePanel') {
        final panelParts = content.split('|');
        if (panelParts.length >= 2) {
          final targetId = panelParts[0];
          final htmlChunk = panelParts[1];

          if (targetId == 'ctl00_ContentPlaceHolder1_UpdatePanel1' ||
              htmlChunk.contains(
                'id="ctl00_ContentPlaceHolder1_grid_contactus"',
              )) {
            updatedHtmlContent = htmlChunk;
            print(
              '  AJAX Delta: Found updatePanel with ID "$targetId" containing grid_contactus HTML.',
            );
          } else {
            print(
              '  AJAX Delta: Found updatePanel with ID "$targetId" (not the main content panel).',
            );
          }
        } else {
          print(
            '  AJAX Delta: Unexpected updatePanel content format: "$content"',
          );
        }
      } else {
        print('  AJAX Delta: Unknown type "$type". Content: "$content"');
      }
    }
    print(
      'Finished parsing AJAX Delta. Parsed hidden fields: ${hiddenFields.keys}',
    );
    return {'updatedHtml': updatedHtmlContent, 'hiddenFields': hiddenFields};
  }
}
