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
        // 🖊️ INI BAGIAN YANG BARU DITAMBAHKAN:
        IconButton(
          icon: const Icon(Icons.edit, color: Colors.blue, size: 26),
          tooltip: 'Edit / Revisi Produk',
          onPressed: () => editProduct(p), // Membuka form dengan data lama
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
)