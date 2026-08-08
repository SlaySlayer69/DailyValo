import '../../../../core/storage/local_store.dart';
import '../../../content/data/models/weapon_skin.dart';
import '../models/wishlist_entry.dart';
import '../wishlist_transfer.dart';

/// The wishlist, persisted in Hive.
///
/// Reads are synchronous — the box is already in memory — which keeps the
/// "is this skin wishlisted?" check on the shop card free of a `FutureBuilder`.
class WishlistRepository {
  WishlistRepository({required LocalStore store}) : _store = store;

  final LocalStore _store;

  /// Newest additions first.
  List<WishlistEntry> getAll() {
    final List<WishlistEntry> entries = _store
        .readWishlist()
        .map(WishlistEntry.fromJson)
        .where((WishlistEntry e) => e.skinUuid.isNotEmpty)
        .toList();
    entries.sort(
      (WishlistEntry a, WishlistEntry b) => b.addedAt.compareTo(a.addedAt),
    );
    return entries;
  }

  bool contains(String skinUuid) => _store.isWishlisted(skinUuid);

  Set<String> get skinUuids => _store.wishlistedSkinUuids();

  /// The level-1 UUIDs, which is what a storefront offer id actually is.
  Set<String> get offerUuids =>
      getAll().map((WishlistEntry e) => e.offerUuid).toSet();

  Future<void> add(WeaponSkin skin) => _store.putWishlistEntry(
    skin.uuid,
    WishlistEntry.fromSkin(skin).toJson(),
  );

  Future<void> remove(String skinUuid) => _store.deleteWishlistEntry(skinUuid);

  /// Puts a removed entry back exactly as it was, keeping its original
  /// `addedAt` so an undo restores its place in the list rather than jumping it
  /// to the top. Takes the entry rather than a skin because undo has to work
  /// when the catalogue is not loaded.
  Future<void> restore(WishlistEntry entry) =>
      _store.putWishlistEntry(entry.skinUuid, entry.toJson());

  /// Returns the entry's new state, so callers can drive a toggle without
  /// re-reading.
  Future<bool> toggle(WeaponSkin skin) async {
    if (contains(skin.uuid)) {
      await remove(skin.uuid);
      return false;
    }
    await add(skin);
    return true;
  }

  /// Adds entries from an export, keeping anything already on the list.
  ///
  /// A merge rather than a replace: importing a friend's list, or an older
  /// backup, should not silently delete what is already there. Existing entries
  /// win, so their original `addedAt` — and with it their place in the list —
  /// survives.
  Future<ImportResult> importEntries(List<WishlistEntry> entries) async {
    int added = 0;
    int present = 0;

    for (final WishlistEntry entry in entries) {
      if (contains(entry.skinUuid)) {
        present++;
        continue;
      }
      await _store.putWishlistEntry(entry.skinUuid, entry.toJson());
      added++;
    }

    return ImportResult(added: added, alreadyPresent: present);
  }

  /// Wishlist entries whose skin is among [offerIds].
  ///
  /// This is the whole of the wishlist-alert rule, and it is deliberately a
  /// pure set operation on denormalised data so the background isolate can run
  /// it with nothing but Hive open.
  List<WishlistEntry> matching(Set<String> offerIds) => getAll()
      .where((WishlistEntry e) => offerIds.contains(e.offerUuid))
      .toList(growable: false);
}
