import 'package:flutter/material.dart';

const double narrowBreakpoint = 800;

bool isNarrow(BuildContext context) =>
    MediaQuery.of(context).size.width < narrowBreakpoint;

bool isWide(BuildContext context) =>
    MediaQuery.of(context).size.width >= narrowBreakpoint;
