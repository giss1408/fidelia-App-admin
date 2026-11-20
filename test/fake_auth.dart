import 'package:fidelia_admin/core/auth/auth_repository.dart';

/// In-memory stand-in for [AuthRepository], for widget and notifier tests.
class FakeAuth implements AuthRepository {
  FakeAuth({this.session = false, this.pc = false, this.signInResult, this.changeError});

  bool session;
  bool pc;
  SignInResult? signInResult;
  String? changeError;

  String? lastTotp;
  String? lastPhone;
  String? lastPassword;
  String? lastCurrent;
  String? lastNew;
  bool signedOut = false;

  @override
  Future<bool> hasValidSession() async => session;
  @override
  Future<String?> currentUsername() async => session ? '+225 ** ** 12' : null;
  @override
  Future<bool> mustChangePassword() async => session && pc;
  @override
  Future<bool> refresh() async => session;
  @override
  bool get authMode => false;
  @override
  Future<void> stepUp({required String password, required String totp}) async {}

  @override
  Future<SignInResult> signIn({required String phone, required String password, String? totp}) async {
    lastTotp = totp;
    lastPhone = phone;
    lastPassword = password;
    final result = signInResult ?? const SignedIn(mustChangePassword: false);
    if (result is SignedIn) {
      session = true;
      pc = result.mustChangePassword;
    }
    return result;
  }

  @override
  Future<void> changePassword({String? current, required String newPassword}) async {
    lastCurrent = current;
    lastNew = newPassword;
    if (changeError != null) throw AccountActionException(changeError!);
    pc = false;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
    session = false;
    pc = false;
  }
}
