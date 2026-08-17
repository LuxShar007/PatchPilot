import 'dart:convert';

/// Represents the strict JSON output contract produced by PatchPilot's diagnostic inference pipeline.
class DiagnosticResult {
  final String rootCause;
  final String targetFile;
  final String explanation;
  final String patchDiff;
  final String testCommand;

  const DiagnosticResult({
    required this.rootCause,
    required this.targetFile,
    required this.explanation,
    required this.patchDiff,
    required this.testCommand,
  });

  /// Factory constructor to parse strictly typed JSON matching the contract
  factory DiagnosticResult.fromJson(Map<String, dynamic> json) {
    return DiagnosticResult(
      rootCause: json['root_cause'] as String? ?? 'Unknown error detected',
      targetFile: json['target_file'] as String? ?? 'unknown_file.py',
      explanation: json['explanation'] as String? ?? 'No explanation provided.',
      patchDiff: json['patch_diff'] as String? ?? '',
      testCommand: json['test_command'] as String? ?? 'pytest',
    );
  }

  /// Converts the model back to the strict JSON map
  Map<String, dynamic> toJson() {
    return {
      'root_cause': rootCause,
      'target_file': targetFile,
      'explanation': explanation,
      'patch_diff': patchDiff,
      'test_command': testCommand,
    };
  }

  /// Returns formatted JSON string
  String toPrettyJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }

  /// Sample mock result matching the prompt specification exactly
  static DiagnosticResult sampleKeyError() {
    return const DiagnosticResult(
      rootCause: "KeyError: 'role' missing in input dictionary",
      targetFile: "app.py",
      explanation: "Added fallback handling for missing user role key.",
      patchDiff: "--- a/app.py\n+++ b/app.py\n@@ -1,7 +1,8 @@\n def process_user_data(user_dict):\n-    return {'name': user_dict['name'], 'role': user_dict['role'].upper(), 'status': 'active'}\n+    role = user_dict.get('role', 'user')\n+    return {'name': user_dict['name'], 'role': role.upper(), 'status': 'active'}\n",
      testCommand: "pytest",
    );
  }

  /// Sample mock for Null Pointer Exception
  static DiagnosticResult sampleNullPointer() {
    return const DiagnosticResult(
      rootCause: "NullPointerException: Attempt to invoke virtual method on a null object reference",
      targetFile: "UserService.java",
      explanation: "Added null check and Optional wrapper before accessing user session profile.",
      patchDiff: "--- a/UserService.java\n+++ b/UserService.java\n@@ -14,6 +14,8 @@\n public UserProfile getProfile(User user) {\n+    if (user == null || user.getSession() == null) {\n+        return UserProfile.anonymous();\n+    }\n     return user.getSession().getProfile();\n }\n",
      testCommand: "mvn test -Dtest=UserServiceTest",
    );
  }

  /// Sample mock for TypeError in JavaScript / TypeScript
  static DiagnosticResult sampleTypeError() {
    return const DiagnosticResult(
      rootCause: "TypeError: Cannot read properties of undefined (reading 'map')",
      targetFile: "src/components/UserList.tsx",
      explanation: "Provided empty array fallback `(items ?? []).map` to prevent undefined access.",
      patchDiff: "--- a/src/components/UserList.tsx\n+++ b/src/components/UserList.tsx\n@@ -22,5 +22,5 @@\n export const UserList = ({ items }: Props) => {\n   return (\n     <div className=\"list-container\">\n-      {items.map(item => <UserCard key={item.id} {...item} />)}\n+      {(items ?? []).map(item => <UserCard key={item.id} {...item} />)}\n     </div>\n   );\n",
      testCommand: "npm test -- --watchAll=false",
    );
  }
}
