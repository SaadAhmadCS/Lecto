import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  void _goToNextScreen() {
    context.go('/onboarding/first-subject');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip Button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.base, right: AppSpacing.base),
                child: _currentPage < 2
                    ? TextButton(
                        onPressed: _goToNextScreen,
                        child: const Text('Skip'),
                      )
                    : const SizedBox(height: 48), // Placeholder to maintain height
              ),
            ),
            
            // PageView Carousel
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (int page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                children: [
                  _buildPage(
                    icon: Icons.mic_rounded,
                    title: 'Record',
                    subtitle: "Place your phone near the speaker and tap record. That's it.",
                  ),
                  _buildPage(
                    icon: Icons.description_rounded,
                    title: 'Transcribe',
                    subtitle: "AI converts your lecture audio into clean, structured text.",
                  ),
                  _buildPage(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Study Notes',
                    subtitle: "Get instant summaries, key concepts, and action items.",
                  ),
                ],
              ),
            ),

            // Bottom Section (Indicators + Get Started)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  // Dot Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      3,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index ? AppColors.primary : AppColors.darkBorder,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: AppSpacing.xxl),
                  
                  // Get Started Button or Next Button spacing
                  SizedBox(
                    height: AppSpacing.minTouchTarget,
                    width: double.infinity,
                    child: _currentPage == 2
                        ? FilledButton(
                            onPressed: _goToNextScreen,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                            ),
                            child: const Text('Get Started'),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 64,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimaryDark,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textSecondaryDark,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
