import 'package:flutter/material.dart';

/// Valor centinela para habilitar el campo de nueva categoría.
const String kNewCategorySentinel = '__new_category__';

/// Normaliza la categoría final a partir del valor elegido y el campo libre.
String resolveSelectedCategory(String selected, String customText) =>
    selected == kNewCategorySentinel ? customText.trim() : selected.trim();

/// Selector reutilizable de categoría con opciones "Sin categoría", categorías
/// ya existentes en el catálogo y "+ Crear nueva categoría...".
class CategoryPickerField extends StatelessWidget {
  const CategoryPickerField({
    super.key,
    required this.existingCategories,
    required this.selectedValue,
    required this.newCategoryController,
    required this.onChanged,
    this.autofocusNewField = false,
  });

  final List<String> existingCategories;
  final String selectedValue;
  final TextEditingController newCategoryController;
  final ValueChanged<String> onChanged;
  final bool autofocusNewField;

  @override
  Widget build(BuildContext context) {
    final normalizedSelected =
        (selectedValue.isEmpty ||
                selectedValue == kNewCategorySentinel ||
                existingCategories.contains(selectedValue))
            ? selectedValue
            : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: normalizedSelected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Categoría'),
          items: [
            const DropdownMenuItem<String>(
              value: '',
              child: Text('Sin categoría'),
            ),
            for (final cat in existingCategories)
              DropdownMenuItem<String>(
                value: cat,
                child: Text(cat, overflow: TextOverflow.ellipsis),
              ),
            DropdownMenuItem<String>(
              value: kNewCategorySentinel,
              child: Text(
                '+ Crear nueva categoría...',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
        if (normalizedSelected == kNewCategorySentinel) ...[
          const SizedBox(height: 10),
          TextField(
            controller: newCategoryController,
            autofocus: autofocusNewField,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Nombre de la nueva categoría',
              hintText: 'Ej. Free Fire, Roblox, Víveres',
              counterText: '',
            ),
          ),
        ],
      ],
    );
  }
}

