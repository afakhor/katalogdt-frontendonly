import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; 
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';

String globalSalesId = 'Sales DT';

final formatRp = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final formatTanggal = DateFormat('dd MMM yyyy', 'id_ID');

void main() async { 
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null); 
  runApp(const KatalogPOApp()); 
}

// --- MODEL KATALOG ---
class KatalogProduct {
  int? dbId;
  String? imagePath; 
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
    required this.salesId,
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
    namaProduk: m['nama_produk'] ?? '',
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
    id: m['id'], 
    namaProduk: m['nama_produk'] ?? '', 
    hargaSatuan: m['harga_satuan'] ?? 0, 
    kuantiti: m['kuantiti'] ?? 1
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

// --- DB HELPER ---
class DBHelper {
  DBHelper._(); static final DBHelper instance = DBHelper._();
  Database? _db;
  Future<Database> get database async {
    if (_db!= null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'katalog_po_v3.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
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
    });
    return _db!;
  }

  Future<int> insertProduct(KatalogProduct p) async {
    final db = await database;
    return db.insert('products', p.toMap());
  }
  
  Future<int> updateProduct(KatalogProduct p) async {
    final db = await database;
    return await db.update('products', p.toMap(), where: 'id = ?', whereArgs: [p.dbId]);
  }

  Future<List<KatalogProduct>> getProducts() async {
    final db = await database;
    final rows = await db.query('products', orderBy: 'id DESC');
    return rows.map((m) => KatalogProduct.fromMap(m)).toList();
  }
  
  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

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
      'nama_toko': po.namaToko,
      'sales_id': po.salesId,
    }, where: 'id =?', whereArgs: [po.dbId]);
    await db.delete('po_items', where: 'po_id =?', whereArgs: [po.dbId]);
    for(final it in po.items){ await db.insert('po_items', it.toMap(po.dbId!)); }
  }
  
  Future<List<POHistory>> getAllPO() async {
    final db = await database;
    final headers = await db.query('po_headers', orderBy: 'id DESC');
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

// --- APP SHELL ---
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
    return Scaffold(
      body: index == 0 ? const CatalogPage() : const HistoryPage(),
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

// --- HALAMAN KATALOG ---
class CatalogPage extends StatefulWidget { const CatalogPage({super.key}); @override State<CatalogPage> createState()=>_CatalogPageState();}
class _CatalogPageState extends State<CatalogPage> {
  List<KatalogProduct> products = [];
  @override void initState(){ super.initState(); loadProducts(); }
  
  Future<void> loadProducts() async {
    final list = await DBHelper.instance.getProducts();
    setState(()=> products = list);
  }
  
  Future<void> addProduct() async {
    final saved = await Navigator.push(context, MaterialPageRoute(builder: (_)=> const ProductFormPage()));
    if(saved == true) loadProducts();
  }

  Future<void> editProduct(KatalogProduct p) async {
    final updated = await Navigator.push(context, MaterialPageRoute(builder: (_)=> ProductFormPage(editProduct: p)));
    if(updated == true) loadProducts();
  }

  void ubahSalesId() {
    final controller = TextEditingController(text: globalSalesId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set ID Sales Global'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'ID Sales Baru')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              setState(() { globalSalesId = controller.text; });
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          )
        ],
      ),
    );
  }

  void konfirmasiHapus(int? id) {
    if (id == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Produk'),
        content: const Text('Apakah Anda yakin ingin menghapus produk ini dari katalog?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(
            onPressed: () async {
              await DBHelper.instance.deleteProduct(id);
              Navigator.pop(ctx);
              loadProducts();
              if(mounted){
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ Produk berhasil dihapus!'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override Widget build(BuildContext context){
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Katalog Produk', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('ID Sales Aktif: $globalSalesId', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.account_circle, size: 30), tooltip: 'Atur ID Sales', onPressed: ubahSalesId),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addProduct,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Tambah Produk'),
      ),
      body: products.isEmpty
       ? Container(
            width: double.infinity, height: double.infinity,
            decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/images/bgdt.png'), fit: BoxFit.cover)),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.all(Radius.circular(12))),
                child: const Text('Belum ada produk.\nTap Tambah Produk untuk mulai.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          )
        : SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  height: isLandscape ? mediaQuery.size.height * 0.5 : 240, 
                  width: double.infinity,
                  decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/images/bgdt.png'), fit: BoxFit.cover)),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: products.map((p) {
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
                          AspectRatio(
                            aspectRatio: 16/9, 
                            child: InteractiveViewer(child: imageWidget),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.namaProduk, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                              const SizedBox(height: 6),
                              Text(p.deskripsi),
                              const SizedBox(height: 10),
                              const Text('Harga Umum', style: TextStyle(fontSize: 12, color: Colors.black54)),
                              Text(formatRp.format(p.hargaNormal), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_)=> POFormPage(pilihProdukAwal: p))), 
                                    icon: const Icon(Icons.edit_note), 
                                    label: const Text('Buat PO')
                                  ),
                                  Row(
                                    children: [
                                      // 🖊️ SEKARANG TOMBOL PENSIL EDIT DISINI (SANGAT JELAS)
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.blue, size: 26),
                                        tooltip: 'Edit / Revisi Produk',
                                        onPressed: () => editProduct(p),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 26),
                                        tooltip: 'Hapus Produk',
                                        onPressed: () => konfirmasiHapus(p.dbId),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ]),
                          )
                        ]),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}

// --- FORM TAMBAH & EDIT PRODUK ---
class ProductFormPage extends StatefulWidget {
  final KatalogProduct? editProduct; 
  const ProductFormPage({super.key, this.editProduct});
  @override State<ProductFormPage> createState()=>_ProductFormPageState();
}
class _ProductFormPageState extends State<ProductFormPage> {
  String? imagePath;
  final namaC = TextEditingController();
  final deskripsiC = TextEditingController();
  final hargaNormalC = TextEditingController();
  final hargaPOC = TextEditingController();
  
  bool get isEdit => widget.editProduct != null;

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      final p = widget.editProduct!;
      imagePath = p.imagePath;
      namaC.text = p.namaProduk;
      deskripsiC.text = p.deskripsi;
      hargaNormalC.text = p.hargaNormal.toString();
      hargaPOC.text = p.hargaPenawaranKhusus.toString();
    }
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if(file!= null){ setState(()=> imagePath = file.path); }
  }

  Future<void> save() async {
    if(namaC.text.isEmpty || hargaNormalC.text.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Nama dan Harga Umum wajib diisi!'), backgroundColor: Colors.red));
      return;
    }
    final p = KatalogProduct(
      dbId: isEdit ? widget.editProduct!.dbId : null, 
      imagePath: imagePath,
      namaProduk: namaC.text,
      deskripsi: deskripsiC.text,
      kategori: 'Umum',
      hargaNormal: int.tryParse(hargaNormalC.text)?? 0,
      hargaPenawaranKhusus: int.tryParse(hargaPOC.text)?? 0,
      salesId: globalSalesId,
    );
    
    if (isEdit) {
      await DBHelper.instance.updateProduct(p); 
    } else {
      await DBHelper.instance.insertProduct(p); 
    }

    if(mounted){ 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEdit ? '✅ Produk berhasil diperbarui!' : '✅ Produk berhasil disimpan!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true); 
    }
  }

  @override Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit / Revisi Produk' : 'Tambah Produk')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // 🔒 KOTAK GAMBAR STATIS (Tidak akan buka folder otomatis kalau diketuk)
        Container(
          height: 180,
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: imagePath == null
           ? const Center(child: Text('Belum ada gambar terpilih', style: TextStyle(color: Colors.black54)))
            : Image.file(File(imagePath!), fit: BoxFit.cover, width: double.infinity),
        ),
        const SizedBox(height: 10),
        
        // 📁 TOMBOL KHUSUS UNTUK UPDATE/PILIH GAMBAR
        ElevatedButton.icon(
          onPressed: pickImage, 
          icon: const Icon(Icons.add_a_photo), 
          label: Text(imagePath == null ? 'Pilih Gambar dari Galeri' : 'Ganti Gambar Produk'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade50, foregroundColor: Colors.blue.shade800),
        ),
        const SizedBox(height: 20),
        
        TextField(controller: namaC, decoration: const InputDecoration(labelText: "Nama Produk", border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: deskripsiC, decoration: const InputDecoration(labelText: "Deskripsi", border: OutlineInputBorder()), maxLines: 3),
        const SizedBox(height: 12),
        TextField(controller: hargaNormalC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Harga Umum / Normal", border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: hargaPOC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Harga Penawaran Khusus", border: OutlineInputBorder())),
        const SizedBox(height: 24),
        
        FilledButton(
          onPressed: save, 
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: Text(isEdit ? 'Simpan Perubahan Harga & Gambar' : 'Simpan ke Katalog')
        ),
      ]),
    );
  }
}

// --- FORM PO ---
class POFormPage extends StatefulWidget {
  final KatalogProduct? pilihProdukAwal;
  final POHistory? editPO;
  const POFormPage({super.key, this.pilihProdukAwal, this.editPO});
  @override State<POFormPage> createState()=>_POFormPageState();
}
class _POFormPageState extends State<POFormPage> {
  late List<POItem> items;
  List<KatalogProduct> listProdukKatalog = [];
  final namaTokoController = TextEditingController();
  bool get isEdit => widget.editPO!= null;

  @override void initState(){
    super.initState();
    loadKatalogOptions();
    if(isEdit){
      final po = widget.editPO!;
      namaTokoController.text = po.namaToko;
      items = po.items.map((e)=>e.copy()).toList();
    } else {
      if(widget.pilihProdukAwal != null){
        items = [POItem(namaProduk: widget.pilihProdukAwal!.namaProduk, hargaSatuan: widget.pilihProdukAwal!.hargaNormal)];
      } else {
        items = [POItem(namaProduk: '', hargaSatuan: 0)];
      }
    }
  }

  Future<void> loadKatalogOptions() async {
    final prods = await DBHelper.instance.getProducts();
    setState(() { listProdukKatalog = prods; });
  }

  int get totalSemua => items.fold(0,(s,e)=>s+e.totalProduk);

  Future<void> simpan() async {
    if(items.any((element) => element.namaProduk.isEmpty)){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Gagal: Pilih barang terlebih dahulu!'), backgroundColor: Colors.red));
      return;
    }
    if(isEdit){
      final po = widget.editPO!;
      po.namaToko = namaTokoController.text;
      po.items = items;
      await DBHelper.instance.updatePO(po);
      if(mounted){ 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ PO Berhasil Diperbarui!'), backgroundColor: Colors.green));
        Navigator.pop(context, true); 
      }
    } else {
      final po = POHistory(
        poCode: 'PO-${DateTime.now().millisecondsSinceEpoch}',
        tanggal: DateTime.now(),
        namaToko: namaTokoController.text.isEmpty? 'Toko Tanpa Nama' : namaTokoController.text,
        items: items,
        salesId: globalSalesId,
      );
      await DBHelper.instance.insertPO(po);
      if(mounted){ 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ PO Berhasil Disimpan!'), backgroundColor: Colors.green));
        Navigator.pop(context, true); 
      }
    }
  }

  @override Widget build(BuildContext context){
    final activeSalesId = isEdit ? widget.editPO!.salesId : globalSalesId;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit? 'Edit PO' : 'Open PO')),
      body: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Opacity(
                opacity: 0.05,
                child: Text(activeSalesId, style: const TextStyle(fontSize: 55, fontWeight: FontWeight.bold, color: Colors.black)),
              ),
            ),
          ),
          ListView(padding: const EdgeInsets.all(16), children: [
            TextField(controller: namaTokoController, decoration: const InputDecoration(labelText: 'Nama Toko:', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            const Text('Item PO (Opsi dari Katalog):', style: TextStyle(fontWeight: FontWeight.w700)),
            ...items.asMap().entries.map((e){
              final indexItem = e.key;
              final it = e.value;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8), 
                child: Padding(padding: const EdgeInsets.all(12), 
                child: Column(children: [
                  DropdownButtonFormField<String>(
                    value: listProdukKatalog.any((p) => p.namaProduk == it.namaProduk) ? it.namaProduk : null,
                    decoration: const InputDecoration(labelText: "Pilih Item Produk", border: UnderlineInputBorder()),
                    hint: const Text("Pilih barang dari katalog"),
                    items: listProdukKatalog.map((prod) {
                      return DropdownMenuItem<String>(value: prod.namaProduk, child: Text(prod.namaProduk));
                    }).toList(),
                    onChanged: (val) {
                      if(val != null) {
                        final selected = listProdukKatalog.firstWhere((p) => p.namaProduk == val);
                        setState(() {
                          it.namaProduk = selected.namaProduk;
                          it.hargaSatuan = selected.hargaNormal;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextFormField(key: Key('${indexItem}_harga_${it.hargaSatuan}'), initialValue: it.hargaSatuan.toString(), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Satuan:'), onChanged: (v)=>setState(()=>it.hargaSatuan=int.tryParse(v)??it.hargaSatuan))),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(initialValue: it.kuantiti.toString(), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kuantiti:'), onChanged: (v)=>setState(()=>it.kuantiti=int.tryParse(v)??1))),
                  ]),
                  Align(alignment: Alignment.centerRight, child: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text('Total Produk: ${formatRp.format(it.totalProduk)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  )),
                ])));
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: ()=>setState(()=>items.add(POItem(namaProduk: '', hargaSatuan: 0))), icon: const Icon(Icons.add), label: const Text('Tambah Item')),
            const Divider(height: 32),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total Semua Produk:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(formatRp.format(totalSemua), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ]),
            const SizedBox(height: 30),
            FilledButton(onPressed: simpan, child: Padding(padding: const EdgeInsets.all(12), child: Text(isEdit? 'Update & Simpan PO' : 'Simpan PO Baru'))),
          ]),
        ],
      ),
    );
  }
}

// --- HALAMAN HISTORY ---
class HistoryPage extends StatefulWidget { const HistoryPage({super.key}); @override State<HistoryPage> createState()=>_HistoryPageState();}
class _HistoryPageState extends State<HistoryPage> {
  List<POHistory> history = []; bool loading = true;
  @override void initState() { super.initState(); loadHistory(); }
  
  Future<void> loadHistory() async { 
    if(!mounted) return;
    setState(()=>loading=true); 
    final list = await DBHelper.instance.getAllPO(); 
    if(!mounted) return;
    setState(() { history = list; loading = false; }); 
  }
  
  Future<void> editPO(POHistory po) async { 
    final updated = await Navigator.push(context, MaterialPageRoute(builder: (_)=> POFormPage(editPO: po))); 
    if(updated == true) loadHistory(); 
  }

  @override Widget build(BuildContext context){
    final Map<String, List<POHistory>> grouped = {};
    for(final po in history){ final key = formatTanggal.format(po.tanggal); grouped.putIfAbsent(key, ()=>[]).add(po); }
    
    return Scaffold(
      appBar: AppBar(title: const Text('History PO', style: TextStyle(fontWeight: FontWeight.w700))),
      body: loading? const Center(child: CircularProgressIndicator())
        : history.isEmpty? const Center(child: Text('Belum ada PO tersimpan.'))
        : RefreshIndicator(
            onRefresh: loadHistory,
            child: ListView(
              padding: const EdgeInsets.all(16), 
              children: grouped.entries.map((entry){
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  ...entry.value.map((po)=> Card(
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Positioned(
                          right: 60, top: 14,
                          child: Opacity(
                            opacity: 0.08,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 2), borderRadius: BorderRadius.circular(4)),
                              child: Text(po.salesId, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ),
                        ExpansionTile(
                          title: Row(
                            children: [
                              Expanded(child: Text(po.namaToko, style: const TextStyle(fontWeight: FontWeight.w600))),
                              IconButton(
                                icon: const Icon(Icons.edit_note, color: Colors.blue, size: 24),
                                tooltip: 'Edit PO ini',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => editPO(po),
                              ),
                            ],
                          ),
                          subtitle: Text('${po.items.length} item - Sales: ${po.salesId}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                          trailing: Text(formatRp.format(po.totalSemua), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFE05A2C))),
                          children: po.items.map((it)=>ListTile(
                            dense: true,
                            title: Text(it.namaProduk),
                            subtitle: Text('${it.kuantiti} x ${formatRp.format(it.hargaSatuan)}'),
                            trailing: Text(formatRp.format(it.totalProduk)),
                          )).toList(),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 12),
                ]);
              }).toList()),
          ),
    );
  }
}