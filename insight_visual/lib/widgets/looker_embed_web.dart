import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:web/web.dart' as web;

class LookerEmbed extends StatefulWidget {
  final String reportUrl;

  const LookerEmbed({super.key, required this.reportUrl});

  @override
  State<LookerEmbed> createState() => _LookerEmbedState();
}

class _LookerEmbedState extends State<LookerEmbed> {
  static final Set<String> _registeredViewTypes = {};

  String get _viewType => 'google-looker-frame-${widget.reportUrl.hashCode}';

  @override
  void initState() {
    super.initState();
    _registerViewFactory();
  }

  void _registerViewFactory() {
    if (_registeredViewTypes.contains(_viewType)) return;
    _registeredViewTypes.add(_viewType);

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) {
        final iframeElement = web.HTMLIFrameElement()
          ..src = widget.reportUrl
          ..allow = 'fullscreen'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
        return iframeElement;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
