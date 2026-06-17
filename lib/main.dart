import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p; // Menggunakan prefix 'p' untuk mencegah bentrokan variabel context
import 'package:image_picker/image_picker.dart';

final formatRp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final formatTanggal = DateFormat('dd MMM yyyy', 'id_ID');

void main() { runApp(const KatalogPOApp()); }

// --- MODEL KATALOG, gambar dari galeri ---
class KatalogProduct {
  int? dbId;
  String? imagePath; // <-- dari galeri, bukan https
  String namaProduk;
  String deskripsi;
  String kategori;
  int hargaNormal;
  int hargaPenawaranKhusus;
  String salesId;
  String sku;
  int stok;
  String satuan;

  KatalogProduct({
    this.dbId,
    this.imagePath,
    required this.namaProduk,
    required this.deskripsi,
    required this.kategori,
    required this.hargaNormal,
    required this.hargaPenawaranKhusus,
    this.salesId = 'Sales DT',
    this.sku = '',
    this.stok = 0,
    this.satuan = 'pcs',
  });

  Map<String, dynamic> toMap() => {
    'image_path': imagePath,
    'nama_produk': namaProduk,
    'deskripsi': deskripsi,
    'kategori': kategori,
    'harga_normal': hargaNormal,
    'harga_penawaran': hargaPenawaranKhusus,
    'sales_id': salesId,
    'sku': sku,
    'stok': stok,
    'satuan': satuan,
  };

  factory KatalogProduct.fromMap(Map<String, dynamic> m) => KatalogProduct(
    dbId: m['id'],
    imagePath: m['image_path'],
    namaProduk: m['nama_produk'],
    deskripsi: m['deskripsi']?? '',
    kategori: m['kategori']?? '',
    hargaNormal: m['harga_normal']?? 0,
    hargaPenawaranKhusus: m['harga_penawaran']?? 0,
    salesId: m['sales_id']?? 'Sales DT',
    sku: m['sku']?? '',
    stok: m['stok']?? 0,
    satuan: m['satuan']?? 'pcs',
  );
}

class POItem {
  int? id;
  String namaProduk;
  int hargaSatuan;
  int kuantiti;
  POItem({this.id, required this.namaProduk, required this.hargaSatuan, this.kuantiti = 1});
  int get totalProduk => hargaSatuan * kuantiti;
  Map<String, dynamic> toMap(int poId) => {
    'po_id': poId,
    'nama_produk': namaProduk,
    'harga_satuan': hargaSatuan,
    'kuantiti': kuantiti,
  };
  factory POItem.fromMap(Map<String, dynamic> m) => POItem(
    id: m['id'], namaProduk: m['nama_produk'], hargaSatuan: m['harga_satuan'], kuantiti: m['kuantiti']
  );
  POItem copy() => POItem(namaProduk: namaProduk, hargaSatuan: hargaSatuan, kuantiti: kuantiti);
}

class POHistory {
  final int? dbId;
  final String poCode;
  DateTime tanggal;
  String namaToko;
  List<POItem> items;
  String salesId;
  POHistory({this.dbId, required this.poCode, required this.tanggal, required this.namaToko, required this.items, required this.salesId});
  int get totalSemua => items.fold(0, (s,e)=>s+e.totalProduk);
}

// --- DB HELPER, sqlite only, no Google Sheet ---
class DBHelper {
  DBHelper._(); static final DBHelper instance = DBHelper._();
  Database? _db;
  Future<Database> get database async {
    if (_db!= null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'katalog_po.db');
    _db = await openDatabase(path, version: 2, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE products(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          image_path TEXT,
          nama_produk TEXT,
          deskripsi TEXT,
          kategori TEXT,
          harga_normal INTEGER,
          harga_penawaran INTEGER,
          sales_id TEXT,
          sku TEXT,
          stok INTEGER,
          satuan TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE po_headers(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          po_code TEXT,
          tanggal TEXT,
          nama_toko TEXT,
          sales_id TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE po_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          po_id INTEGER,
          nama_produk TEXT,
          harga_satuan INTEGER,
          kuantiti INTEGER,
          FOREIGN KEY(po_id) REFERENCES po_headers(id) ON DELETE CASCADE
        )
      ''');
    }, onUpgrade: (db, oldV, newV) async {
      if(oldV < 2){
        await db.execute('''
        CREATE TABLE IF NOT EXISTS products(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          image_path TEXT,
          nama_produk TEXT,
          deskripsi TEXT,
          kategori TEXT,
          harga_normal INTEGER,
          harga_penawaran INTEGER,
          sales_id TEXT,
          sku TEXT,
          stok INTEGER,
          satuan TEXT
        )''');
      }
    });
    return _db!;
  }
  // Produk
  Future<int> insertProduct(KatalogProduct p) async {
    final db = await database;
    return db.insert('products', p.toMap());
  }
  Future<List<KatalogProduct>> getProducts() async {
    final db = await database;
    final rows = await db.query('products', orderBy: 'id DESC');
    return rows.map((m) => KatalogProduct.fromMap(m)).toList();
  }

  // PO
  Future<int> insertPO(POHistory po) async {
    final db = await database;
    final poId = await db.insert('po_headers', {
      'po_code': po.poCode,
      'tanggal': po.tanggal.toIso8601String(),
      'nama_toko': po.namaToko,
      'sales_id': po.salesId,
    });
    for(final it in po.items){ await db.insert('po_items', it.toMap(poId)); }
    return poId;
  }
  Future<void> updatePO(POHistory po) async {
    final db = await database;
    if(po.dbId == null) return;
    await db.update('po_headers', {
      'tanggal': DateTime.now().toIso8601String(),
      'nama_toko': po.namaToko,
      'sales_id': po.salesId,
    }, where: 'id =?', whereArgs: [po.dbId]);
    await db.delete('po_items', where: 'po_id =?', whereArgs: [po.dbId]);
    for(final it in po.items){ await db.insert('po_items', it.toMap(po.dbId!)); }
  }
  Future<List<POHistory>> getAllPO() async {
    final db = await database;
    final headers = await db.query('po_headers', orderBy: 'tanggal DESC');
    List<POHistory> result = [];
    for(final h in headers){
      final poId = h['id'] as int;
      final itemsMap = await db.query('po_items', where: 'po_id =?', whereArgs: [poId]);
      result.add(POHistory(
        dbId: poId,
        poCode: h['po_code'] as String,
        tanggal: DateTime.parse(h['tanggal'] as String),
        namaToko: h['nama_toko'] as String,
        salesId: h['sales_id'] as String,
        items: itemsMap.map((m)=>POItem.fromMap(m)).toList(),
      ));
    }
    return result;
  }
}

// --- APP ---
class KatalogPOApp extends StatelessWidget {
  const KatalogPOApp({super.key});
  @override Widget build(BuildContext context){
    return MaterialApp(
      title: 'Katalog PO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE05A2C)), useMaterial3: true),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget { const HomeShell({super.key}); @override State<HomeShell> createState()=>_HomeShellState();}
class _HomeShellState extends State<HomeShell> {
  int index = 0;
  @override Widget build(BuildContext context){
    final pages = [const CatalogPage(), const HistoryPage()];
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i)=>setState(()=>index=i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Katalog'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'History PO'),
        ],
      ),
    );
  }
}

// --- HALAMAN 1: KATALOG, gambar dari galeri ---
class CatalogPage extends StatefulWidget { const CatalogPage({super.key}); @override State<CatalogPage> createState()=>_CatalogPageState();}
class _CatalogPageState extends State<CatalogPage> {
  List<KatalogProduct> products = [];
  @override void initState(){ super.initState(); loadProducts(); }
  Future<void> loadProducts() async {
    final list = await DBHelper.instance.getProducts();
    setState(()=> products = list);
  }
  void openPO(KatalogProduct p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_)=> POFormPage(product: p)));
    setState((){});
  }
  Future<void> addProduct() async {
    final saved = await Navigator.push(context, MaterialPageRoute(builder: (_)=> const ProductFormPage()));
    if(saved == true) loadProducts();
  }
  @override Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text('Katalog Produk', style: TextStyle(fontWeight: FontWeight.w700))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addProduct,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Tambah Produk'),
      ),
      body: products.isEmpty
       ? const Center(child: Text('Belum ada produk.\nTap Tambah Produk untuk input dari Galeri.', textAlign: TextAlign.center))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            itemBuilder: (context, i){
              final p = products[i];
              Widget imageWidget;
              if(p.imagePath!= null && File(p.imagePath!).existsSync()){
                imageWidget = Image.file(File(p.imagePath!), fit: BoxFit.cover, width: double.infinity);
              } else {
                imageWidget = Container(color: Colors.grey.shade200, child: const Icon(Icons.image, size: 48));
              }
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                clipBehavior: Clip.antiAlias,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AspectRatio(aspectRatio: 16/9, child: imageWidget),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      InkWell(
                        onTap: ()=>openPO(p),
                        child: Text(p.namaProduk, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                      ),
                      const SizedBox(height: 6),
                      Text(p.deskripsi),
                      const SizedBox(height: 10),
                      Text('Harga Penawaran Khusus ${p.salesId}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      Text(formatRp.format(p.hargaPenawaranKhusus), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      FilledButton.icon(onPressed: ()=>openPO(p), icon: const Icon(Icons.edit_note), label: const Text('Buat PO')),
                    ]),
                  )
                ]),
              );
            }),
    );
  }
}

// --- FORM TAMBAH PRODUK, gambar dari galeri ---
class ProductFormPage extends StatefulWidget {
  const ProductFormPage({super.key});
  @override State<ProductFormPage> createState()=>_ProductFormPageState();
}
class _ProductFormPageState extends State<ProductFormPage> {
  String? imagePath;
  final namaC = TextEditingController();
  final deskripsiC = TextEditingController();
  final hargaNormalC = TextEditingController();
  final hargaPOC = TextEditingController(); // Memperbaiki typo nama variabel 'hargaPO C'
  final salesC = TextEditingController(text: 'Sales DT');

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if(file!= null){ setState(()=> imagePath = file.path); }
  }

  Future<void> save() async {
    final p = KatalogProduct(
      imagePath: imagePath,
      namaProduk: namaC.text,
      deskripsi: deskripsiC.text,
      kategori: 'Umum',
      hargaNormal: int.tryParse(hargaNormalC.text)?? 0,
      hargaPenawaranKhusus: int.tryParse(hargaPOC.text)?? 0,
      salesId: salesC.text,
    );
    await DBHelper.instance.insertProduct(p);
    if(mounted){ Navigator.pop(context, true); }
  }

  @override Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Produk')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GestureDetector(
          onTap: pickImage,
          child: Container(
            height: 180,
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: imagePath == null
             ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, size: 40), Text('Tap untuk pilih gambar dari Galeri')]))
              : Image.file(File(imagePath!), fit: BoxFit.cover, width: double.infinity),
          ),
        ),
        const SizedBox(height: 16),
        TextField(controller: namaC, decoration: const InputDecoration(labelText: "nama produk", border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: deskripsiC, decoration: const InputDecoration(labelText: "deskripsi", border: OutlineInputBorder()), maxLines: 3),
        const SizedBox(height: 12),
        TextField(controller: hargaNormalC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Harga Normal", border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: hargaPOC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Harga Penawaran Khusus", border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: salesC, decoration: const InputDecoration(labelText: "{ id nama sales }", border: OutlineInputBorder())),
        const SizedBox(height: 20),
        FilledButton(onPressed: save, child: const Text('Simpan Produk')),
      ]),
    );
  }
}

// --- FORM PO, sama seperti sebelumnya, sqlite ---
class POFormPage extends StatefulWidget {
  final KatalogProduct? product;
  final POHistory? editPO;
  const POFormPage({super.key, this.product, this.editPO});
  @override State<POFormPage> createState()=>_POFormPageState();
}
class _POFormPageState extends State<POFormPage> {
  late List<POItem> items;
  final namaTokoController = TextEditingController();
  late TextEditingController salesController;
  bool get isEdit => widget.editPO!= null;

  @override void initState(){
    super.initState();
    if(isEdit){
      final po = widget.editPO!;
      namaTokoController.text = po.namaToko;
      salesController = TextEditingController(text: po.salesId);
      items = po.items.map((e)=>e.copy()).toList();
    } else {
      final p = widget.product!;
      salesController = TextEditingController(text: p.salesId);
      items = [POItem(namaProduk: p.namaProduk, hargaSatuan: p.hargaPenawaranKhusus)];
    }
  }
  int get totalSemua => items.fold(0,(s,e)=>s+e.totalProduk);

  Future<void> simpan() async {
    if(isEdit){
      final po = widget.editPO!;
      po.namaToko = namaTokoController.text;
      po.items = items;
      po.salesId = salesController.text;
      await DBHelper.instance.updatePO(po);
      if(mounted){ Navigator.pop(context, true); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PO berhasil diupdate'))); }
    } else {
      final po = POHistory(
        poCode: 'PO-${DateTime.now().millisecondsSinceEpoch}',
        tanggal: DateTime.now(),
        namaToko: namaTokoController.text.isEmpty? 'Toko Tanpa Nama' : namaTokoController.text,
        items: items.map((e)=>e.copy()).toList(),
        salesId: salesController.text,
      );
      await DBHelper.instance.insertPO(po);
      if(mounted){ Navigator.pop(context, true); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PO tersimpan. Total ${formatRp.format(po.totalSemua)}'))); }
    }
  }
  @override Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text(isEdit? 'Edit PO' : 'Open PO')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: namaTokoController, decoration: const InputDecoration(labelText: 'nama toko:', border: OutlineInputBorder())),
        const SizedBox(height: 20),
        const Text('Item PO:', style: TextStyle(fontWeight: FontWeight.w700)),
       ...items.asMap().entries.map((e){
          final it = e.value;
          return Card(margin: const EdgeInsets.symmetric(vertical: 8), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            TextFormField(initialValue: it.namaProduk, decoration: const InputDecoration(labelText: "item 'nama produk':"), onChanged: (v)=>it.namaProduk=v),
            Row(children: [
              Expanded(child: TextFormField(initialValue: it.hargaSatuan.toString(), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'harga satuan:'), onChanged: (v)=>setState(()=>it.hargaSatuan=int.tryParse(v)??it.hargaSatuan))),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(initialValue: it.kuantiti.toString(), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'kuantiti:'), onChanged: (v)=>setState(()=>it.kuantiti=int.tryParse(v)??1))),
            ]),
            Align(alignment: Alignment.centerRight, child: Text('total produk: ${formatRp.format(it.totalProduk)}', style: const TextStyle(fontWeight: FontWeight.w600))),
          ]))); // Memperbaiki penutup kurung dan menambahkan titik koma untuk return di dalam map
        }),
        OutlinedButton.icon(onPressed: ()=>setState(()=>items.add(POItem(namaProduk: '', hargaSatuan: 0))), icon: const Icon(Icons.add), label: const Text('Tambah item')),
        const Divider(height: 32),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total Semua Produk:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          Text(formatRp.format(totalSemua), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        const SizedBox(height: 16),
        TextField(controller: salesController, decoration: const InputDecoration(labelText: '{ id nama sales }', border: OutlineInputBorder())),
        const SizedBox(height: 20),
        FilledButton(onPressed: simpan, child: Padding(padding: const EdgeInsets.all(12), child: Text(isEdit? 'Update PO' : 'Simpan PO'))),
      ]),
    );
  }
}

// --- HALAMAN 2: HISTORY ---
class HistoryPage extends StatefulWidget { const HistoryPage({super.key}); @override State<HistoryPage> createState()=>_HistoryPageState();}
class _HistoryPageState extends State<HistoryPage> {
  List<POHistory> history = []; bool loading = true;
  @override void initState(){ super.initState(); loadHistory(); }
  Future<void> loadHistory() async { setState(()=>loading=true); history = await DBHelper.instance.getAllPO(); setState(()=>loading=false); }
  Future<void> editPO(POHistory po) async { final updated = await Navigator.push(context, MaterialPageRoute(builder: (_)=> POFormPage(editPO: po))); if(updated == true) loadHistory(); }
  @override Widget build(BuildContext context){
    final Map<String, List<POHistory>> grouped = {};
    for(final po in history){ final key = formatTanggal.format(po.tanggal); grouped.putIfAbsent(key, ()=>[]).add(po); }
    return Scaffold(
      appBar: AppBar(title: const Text('History PO', style: TextStyle(fontWeight: FontWeight.w700))),
      body: loading? const Center(child: CircularProgressIndicator())
        : history.isEmpty? const Center(child: Text('Belum ada PO tersimpan'))
        : RefreshIndicator(
            onRefresh: loadHistory,
            child: ListView(padding: const EdgeInsets.all(16), children: grouped.entries.map((entry){
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
               ...entry.value.map((po)=> Card(child: ExpansionTile(
                  title: Text(po.namaToko, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${po.items.length} item'),
                    ActionChip(
                      label: Text(po.salesId),
                      avatar: const Icon(Icons.edit, size: 16),
                      onPressed: ()=>editPO(po),
                    ),
                  ]),
                  trailing: Text(formatRp.format(po.totalSemua), style: const TextStyle(fontWeight: FontWeight.w700)),
                  children: po.items.map((it)=>ListTile(
                    dense: true,
                    title: Text(it.namaProduk),
                    subtitle: Text('${it.kuantiti} x ${formatRp.format(it.hargaSatuan)}'),
                    trailing: Text(formatRp.format(it.totalProduk)),
                  )).toList(),
                ))),
                const SizedBox(height: 12),
              ]);
            }).toList()),
          ),
    );
  }
}
