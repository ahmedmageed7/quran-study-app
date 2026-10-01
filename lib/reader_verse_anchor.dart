import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Registers only mounted verse boxes, including the sliver's cache area.
/// The reader checks their actual viewport intersection after layout.
class ReaderVerseAnchor extends SingleChildRenderObjectWidget {
  const ReaderVerseAnchor({
    super.key,
    required this.index,
    required this.onAttach,
    required this.onDetach,
    required super.child,
  });

  final int index;
  final void Function(int, RenderBox) onAttach;
  final void Function(int) onDetach;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _VerseBox(index, onAttach, onDetach);
}

class _VerseBox extends RenderProxyBox {
  _VerseBox(this.index, this.onAttach, this.onDetach);
  final int index;
  final void Function(int, RenderBox) onAttach;
  final void Function(int) onDetach;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    onAttach(index, this);
  }

  @override
  void detach() {
    onDetach(index);
    super.detach();
  }
}
