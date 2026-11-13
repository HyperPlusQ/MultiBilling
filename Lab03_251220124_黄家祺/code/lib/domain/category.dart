import 'domain_exception.dart';
import 'enums.dart';

/// 收支类别，对应类图中的 `Category`。
///
/// 类别绑定单一方向，避免同一类别在收入和支出两侧语义不同。
class Category {
  Category({
    required this.categoryId,
    required this.ledgerId,
    required this.name,
    required this.direction,
    required this.color,
    required this.sortNo,
  }) {
    if (name.trim().isEmpty) {
      throw ValidationException('类别名称不能为空', field: 'categoryName');
    }
    if (!_colorPattern.hasMatch(color)) {
      throw ValidationException('颜色需为 #RRGGBB 格式', field: 'color');
    }
  }

  /// 从 JSON 还原。
  factory Category.fromJson(Map<String, Object?> json) => Category(
    categoryId: json['categoryId']! as int,
    ledgerId: json['ledgerId']! as int,
    name: json['name']! as String,
    direction: EntryDirection.values.byName(json['direction']! as String),
    color: json['color']! as String,
    sortNo: json['sortNo']! as int,
  );

  static final RegExp _colorPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

  /// 主键。
  final int categoryId;

  /// 所属账本。
  final int ledgerId;

  /// 类别名，账本内唯一。
  String name;

  /// 收支方向。
  EntryDirection direction;

  /// 图表与标签用的十六进制颜色。
  String color;

  /// 展示顺序。
  int sortNo;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'categoryId': categoryId,
    'ledgerId': ledgerId,
    'name': name,
    'direction': direction.name,
    'color': color,
    'sortNo': sortNo,
  };

  @override
  String toString() => 'Category($categoryId, $name)';
}

/// 内置类别模板，创建账本时按方向批量生成，省去用户从零录入。
class DefaultCategories {
  /// 返回账本初始化时应创建的类别列表数据。
  static List<Category> forLedger(int ledgerId, int startId) {
    var nextId = startId;
    var sort = 0;
    final result = <Category>[];
    for (final spec in _expenseSpecs) {
      result.add(
        Category(
          categoryId: nextId++,
          ledgerId: ledgerId,
          name: spec.$1,
          direction: EntryDirection.expense,
          color: spec.$2,
          sortNo: sort++,
        ),
      );
    }
    sort = 0;
    for (final spec in _incomeSpecs) {
      result.add(
        Category(
          categoryId: nextId++,
          ledgerId: ledgerId,
          name: spec.$1,
          direction: EntryDirection.income,
          color: spec.$2,
          sortNo: sort++,
        ),
      );
    }
    return result;
  }

  static const List<(String, String)> _expenseSpecs = <(String, String)>[
    ('餐饮', '#EF6C00'),
    ('交通', '#1E88E5'),
    ('办公', '#8E24AA'),
    ('活动', '#43A047'),
    ('其他支出', '#757575'),
  ];

  static const List<(String, String)> _incomeSpecs = <(String, String)>[
    ('班费', '#00897B'),
    ('赞助', '#F4511E'),
    ('补贴', '#3949AB'),
    ('其他收入', '#546E7A'),
  ];
}
