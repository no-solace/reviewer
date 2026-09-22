import 'package:xml/xml.dart';

/// Small helpers for reading OOXML (`.docx`) XML by local element/attribute
/// name, ignoring namespace prefixes — Word always uses "w:", but other
/// tools that produce `.docx` files may declare a different prefix for the
/// same namespace.

XmlElement? ooxmlChild(XmlElement element, String localName) {
  for (final child in element.childElements) {
    if (child.name.local == localName) return child;
  }
  return null;
}

Iterable<XmlElement> ooxmlChildren(XmlElement element, String localName) {
  return element.childElements.where((e) => e.name.local == localName);
}

Iterable<XmlElement> ooxmlDescendants(XmlElement element, String localName) {
  return element.descendants.whereType<XmlElement>().where((e) => e.name.local == localName);
}

String? ooxmlAttr(XmlElement element, String localName) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == localName) return attribute.value;
  }
  return null;
}
