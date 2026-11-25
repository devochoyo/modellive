import 'package:flutter/material.dart';

import '../model/country_model.dart';
import '../screens/colors.dart';

// Opens a bottom sheet with a search box and every country.
// Returns the country the user taps, or null if the sheet is closed.
Future<CountryModel?> showCountryPicker(
  BuildContext context, {
  CountryModel? selected,
}) {
  return showModalBottomSheet<CountryModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _CountryPickerSheet(selected: selected),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  final CountryModel? selected;

  const _CountryPickerSheet({required this.selected});

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Typing "nig" shows Nigeria and Niger. Typing a code like "NG" works too.
  List<CountryModel> get _results {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return CountryModel.all;
    return CountryModel.all
        .where((country) =>
            country.name.toLowerCase().contains(query) ||
            country.code.toLowerCase() == query)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    // 80% of the screen, but never taller than the space above the keyboard.
    final sheetHeight = (screen.height * 0.8) < (screen.height - keyboard - 60)
        ? screen.height * 0.8
        : screen.height - keyboard - 60;
    final results = _results;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.softPink,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Country',
              style: TextStyle(
                color: AppColors.deepPink,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search your country',
                  hintStyle:
                      const TextStyle(color: AppColors.softGrey, fontSize: 15),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.softGrey, size: 22),
                  filled: true,
                  fillColor: AppColors.blushBackground,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  enabledBorder: _border(AppColors.softPink),
                  focusedBorder: _border(AppColors.primaryPink, 1.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: results.isEmpty
                  ? const Center(
                      child: Text(
                        'No country found.',
                        style:
                            TextStyle(color: AppColors.softGrey, fontSize: 15),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: results.length,
                      itemBuilder: (context, index) =>
                          _buildCountryRow(results[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  Widget _buildCountryRow(CountryModel country) {
    final isSelected = country.code == widget.selected?.code;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.pop(context, country),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.softPink : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Text(country.flag, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                country.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.darkBackground,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.primaryPink, size: 22),
          ],
        ),
      ),
    );
  }
}
