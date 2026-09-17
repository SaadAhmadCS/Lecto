import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/errors/error_messages.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

class FirstSubjectScreen extends StatefulWidget {
  const FirstSubjectScreen({super.key});

  @override
  State<FirstSubjectScreen> createState() => _FirstSubjectScreenState();
}

class _FirstSubjectScreenState extends State<FirstSubjectScreen> {
  final TextEditingController _nameController = TextEditingController();
  Color _selectedColor = AppColors.subjectColors[0];
  bool _isLoading = false;

  final List<String> _suggestions = [
    'Math',
    'Physics',
    'Computer Science',
    'Biology',
    'History',
    'English',
    'Chemistry',
    'Psychology',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasCompletedOnboarding', true);
    if (mounted) {
      context.go('/home');
    }
  }

  Future<void> _createSubject() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final apiClient = context.read<LectoApiClient>();
      
      final hexColor = '#${_selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
      
      await apiClient.createSubject(
        name: name,
        color: hexColor,
      );
      
      await _completeOnboarding();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.from(e, action: 'create the subject'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _completeOnboarding,
            child: const Text('Skip for now'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create Your First Subject',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryDark,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Organize your recordings by class or topic',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondaryDark,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              
              // Name Input
              TextField(
                controller: _nameController,
                style: const TextStyle(color: AppColors.textPrimaryDark),
                decoration: InputDecoration(
                  labelText: 'Subject Name',
                  hintText: 'e.g. Linear Algebra',
                  filled: true,
                  fillColor: AppColors.darkSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              
              // Suggestions
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _suggestions.map((suggestion) {
                  return ActionChip(
                    label: Text(suggestion),
                    backgroundColor: AppColors.darkSurfaceLight,
                    onPressed: () {
                      setState(() {
                        _nameController.text = suggestion;
                      });
                    },
                  );
                }).toList(),
              ),
              
              const SizedBox(height: AppSpacing.xxl),
              
              // Color Picker
              const Text(
                'Choose a color',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryDark,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: AppColors.subjectColors.map((color) {
                  final isSelected = color == _selectedColor;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedColor = color;
                      });
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              
              const SizedBox(height: AppSpacing.massive),
              
              // Create Button
              SizedBox(
                width: double.infinity,
                height: AppSpacing.minTouchTarget,
                child: FilledButton(
                  onPressed: _isLoading ? null : _createSubject,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Create & Start'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
