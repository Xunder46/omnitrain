import 'package:flutter/material.dart';

import '../../../state/settings/settings_state.dart';

class InteractiveLogo extends StatefulWidget {
  final VoidCallback onTap;
  final SettingsState settingsState;

  const InteractiveLogo({
    super.key,
    required this.onTap,
    required this.settingsState,
  });

  @override
  _InteractiveLogoState createState() => _InteractiveLogoState();
}

class _InteractiveLogoState extends State<InteractiveLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (MediaQuery.of(context).disableAnimations) {
      setState(() => _isPressed = true);
    } else {
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (MediaQuery.of(context).disableAnimations) {
      setState(() => _isPressed = false);
    } else {
      _controller.reverse();
    }
  }

  void _handleTapCancel() {
    if (MediaQuery.of(context).disableAnimations) {
      setState(() => _isPressed = false);
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final logo = Image.asset(
      'assets/icon/omnitrain_logo.png',
      width: 48,
      height: 48,
    );

    Widget content = ListenableBuilder(
      listenable: widget.settingsState,
      builder: (context, child) {
        final showLabel = widget.settingsState.showHubLabel;
        return Stack(
          alignment: Alignment.center,
          children: [
            child!,
            if (showLabel)
              const Text(
                'Hub',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
          ],
        );
      },
      child: logo,
    );

    if (!reduceMotion) {
      content = ScaleTransition(scale: _scaleAnimation, child: content);
    } else if (_isPressed) {
      content = Transform.scale(scale: 0.9, child: content);
    }

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: content,
    );
  }
}
