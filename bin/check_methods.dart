import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dart:io';

void main() {
  SfPdfViewer.file(
    File(''),
    password: 'test',
    canShowScrollHead: true,
  );
}
