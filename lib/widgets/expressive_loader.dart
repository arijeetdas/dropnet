import 'package:flutter/material.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';

class ExpressiveLoader extends StatelessWidget {
  const ExpressiveLoader({
    super.key,
    this.color,
    this.variant = LoadingIndicatorM3EVariant.defaultStyle,
  });

  final Color? color;
  final LoadingIndicatorM3EVariant variant;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LoadingIndicatorM3E(
        color: color,
        variant: variant,
      ),
    );
  }
}
