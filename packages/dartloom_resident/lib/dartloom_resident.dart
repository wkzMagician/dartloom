abstract interface class ResidentService {
  Future<void> initialize({required String iconPath});
  Future<void> restore();
  Future<void> quit();
  Future<void> dispose();
}
