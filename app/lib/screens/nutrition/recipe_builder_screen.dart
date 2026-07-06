import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/nutrition_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/z/z_card.dart';

String _fmt(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Create or edit a multi-ingredient recipe. Ingredients are searched from the
/// food DB; macros roll up live. Save persists via NutritionService.
class RecipeBuilderScreen extends StatefulWidget {
  const RecipeBuilderScreen({super.key, this.editing});
  final Recipe? editing;

  @override
  State<RecipeBuilderScreen> createState() => _RecipeBuilderScreenState();
}

class _RecipeBuilderScreenState extends State<RecipeBuilderScreen> {
  final _service = NutritionService.instance;
  final _name = TextEditingController();
  int _servings = 1;
  final List<RecipeIngredient> _ingredients = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _name.text = e.name;
      _servings = e.servings;
      _ingredients.addAll(e.ingredients);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  double get _totalCal => _ingredients.fold(0, (s, i) => s + i.calories);
  double get _totalP => _ingredients.fold(0, (s, i) => s + i.protein);
  double get _totalC => _ingredients.fold(0, (s, i) => s + i.carbs);
  double get _totalF => _ingredients.fold(0, (s, i) => s + i.fat);

  Future<void> _addIngredient() async {
    final ing = await showModalBottomSheet<RecipeIngredient>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _IngredientPickerSheet(),
    );
    if (!mounted || ing == null) return;
    setState(() => _ingredients.add(ing));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the recipe a name');
      return;
    }
    if (_ingredients.isEmpty) {
      setState(() => _error = 'Add at least one ingredient');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final editing = widget.editing;
      final saved = editing == null
          ? await _service.createRecipe(name: name, servings: _servings, ingredients: _ingredients)
          : await _service.updateRecipe(editing.id, name: name, servings: _servings, ingredients: _ingredients);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final perServ = _servings > 0 ? _totalCal / _servings : _totalCal;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        title: Text(widget.editing == null ? 'New Recipe' : 'Edit Recipe',
            style: ZType.h4.copyWith(color: ZveltTokens.text)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              ZveltTokens.screenPaddingH, ZveltTokens.s4, ZveltTokens.screenPaddingH, ZveltTokens.s10),
          children: [
            TextField(
              controller: _name,
              style: ZType.bodyM.copyWith(color: ZveltTokens.text),
              decoration: InputDecoration(
                hintText: 'Recipe name',
                hintStyle: ZType.bodyS.copyWith(color: ZveltTokens.text3),
                filled: true,
                fillColor: ZveltTokens.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZveltTokens.rMd), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: ZveltTokens.s4),
            ZCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Servings', style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
                      const Spacer(),
                      _StepBtn(icon: AppIcons.minus, onTap: () => setState(() => _servings = (_servings - 1).clamp(1, 50))),
                      SizedBox(
                        width: 40,
                        child: Text('$_servings',
                            textAlign: TextAlign.center, style: ZType.num_.copyWith(color: ZveltTokens.text, fontSize: 18)),
                      ),
                      _StepBtn(icon: AppIcons.plus, onTap: () => setState(() => _servings = (_servings + 1).clamp(1, 50))),
                    ],
                  ),
                  Divider(height: ZveltTokens.s5, thickness: 0.5, color: ZveltTokens.hairline),
                  Row(
                    children: [
                      _macro('Total', '${_totalCal.round()} kcal'),
                      _macro('Per serving', '${perServ.round()} kcal'),
                    ],
                  ),
                  const SizedBox(height: ZveltTokens.s2),
                  Text('P ${_fmt(_totalP)}g · C ${_fmt(_totalC)}g · G ${_fmt(_totalF)}g',
                      style: ZType.monoS.copyWith(color: ZveltTokens.text2)),
                ],
              ),
            ),
            const SizedBox(height: ZveltTokens.s4),
            Row(
              children: [
                Text('INGREDIENTS', style: ZType.eyebrow.copyWith(color: ZveltTokens.text3)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addIngredient,
                  icon: const Icon(AppIcons.plus, size: 16),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_ingredients.isEmpty)
              Padding(
                padding: const EdgeInsets.all(ZveltTokens.s4),
                child: Text('No ingredients yet.', style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
              )
            else
              for (int i = 0; i < _ingredients.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_ingredients[i].name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
                  subtitle: Text('${_fmt(_ingredients[i].grams)} g · ${_ingredients[i].calories.round()} kcal',
                      style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                  trailing: IconButton(
                    icon: Icon(AppIcons.trash, color: ZveltTokens.text3, size: 18),
                    onPressed: () => setState(() => _ingredients.removeAt(i)),
                  ),
                ),
            if (_error != null) ...[
              const SizedBox(height: ZveltTokens.s2),
              Text(_error!, style: ZType.bodyS.copyWith(color: ZveltTokens.error)),
            ],
            const SizedBox(height: ZveltTokens.s5),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rMd))),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: ZveltTokens.onBrand))
                    : Text('Save recipe',
                        style: ZType.bodyM.copyWith(color: ZveltTokens.onBrand, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _macro(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: ZType.bodyS.copyWith(color: ZveltTokens.text3, fontSize: 11)),
            Text(value, style: ZType.num_.copyWith(color: ZveltTokens.text, fontSize: 18)),
          ],
        ),
      );
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: ZveltTokens.bg2, borderRadius: BorderRadius.circular(ZveltTokens.rSm)),
        child: Icon(icon, color: ZveltTokens.text, size: 16),
      ),
    );
  }
}

/// Search a food and pick grams → returns a RecipeIngredient.
class _IngredientPickerSheet extends StatefulWidget {
  const _IngredientPickerSheet();
  @override
  State<_IngredientPickerSheet> createState() => _IngredientPickerSheetState();
}

class _IngredientPickerSheetState extends State<_IngredientPickerSheet> {
  final _service = NutritionService.instance;
  final _ctrl = TextEditingController();
  List<FoodItem> _results = [];
  bool _loading = false;
  int _gen = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final t = q.trim();
    if (t.length < 3) {
      setState(() => _results = []);
      return;
    }
    final gen = ++_gen;
    setState(() => _loading = true);
    final out = await _service.searchByName(t);
    if (!mounted || gen != _gen) return;
    setState(() {
      _results = out.items;
      _loading = false;
    });
  }

  Future<void> _pick(FoodItem food) async {
    final grams = await showDialog<double>(
      context: context,
      builder: (_) => _GramsDialog(food: food),
    );
    if (!mounted || grams == null) return;
    Navigator.of(context).pop(RecipeIngredient.fromFood(food, grams));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        ),
        padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s4),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: ZveltTokens.s3),
                decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
              ),
            ),
            TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _search,
              style: ZType.bodyM.copyWith(color: ZveltTokens.text),
              decoration: InputDecoration(
                hintText: 'Search ingredient…',
                hintStyle: ZType.bodyM.copyWith(color: ZveltTokens.text3),
                prefixIcon: Icon(AppIcons.search, color: ZveltTokens.text3, size: 20),
                filled: true,
                fillColor: ZveltTokens.surface2,
                contentPadding: const EdgeInsets.symmetric(vertical: ZveltTokens.s3, horizontal: ZveltTokens.s3),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZveltTokens.rPill), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: ZveltTokens.s2),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final f = _results[i];
                        return ListTile(
                          title: Text(f.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: ZType.bodyM.copyWith(color: ZveltTokens.text, fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text('${f.caloriesPer100g.round()} kcal/100g',
                              style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 12)),
                          trailing: const Icon(AppIcons.plus, color: ZveltTokens.brand, size: 20),
                          onTap: () => _pick(f),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GramsDialog extends StatefulWidget {
  const _GramsDialog({required this.food});
  final FoodItem food;
  @override
  State<_GramsDialog> createState() => _GramsDialogState();
}

class _GramsDialogState extends State<_GramsDialog> {
  final _ctrl = TextEditingController(text: '100');
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ZveltTokens.surface,
      title: Text(widget.food.name, style: ZType.h4.copyWith(color: ZveltTokens.text)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: ZType.num_.copyWith(color: ZveltTokens.text),
        decoration: const InputDecoration(suffixText: 'g'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: ZveltTokens.brand, foregroundColor: ZveltTokens.onBrand),
          onPressed: () {
            final g = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
            Navigator.pop(context, (g != null && g > 0) ? g : null);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
