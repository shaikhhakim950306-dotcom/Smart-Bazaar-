import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'utils/localization.dart';
import 'services/cart_provider.dart';
import 'models/product_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init: Ensure google-services.json is added: $e");
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppLanguage()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: const SmartBazaarApp(),
    ),
  );
}

class SmartBazaarApp extends StatelessWidget {
  const SmartBazaarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Bazaar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2874F0)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const AuthScreen();

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(snapshot.data!.uid).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final role = userSnap.data?.get('role') ?? 'customer';
            if (role == 'admin') return const AdminDashboard();
            if (role == 'seller') return const SellerDashboard();
            return const CustomerHomeScreen();
          },
        );
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String _selectedRole = 'customer';
  bool _isSignUp = false;

  Future<void> _submit() async {
    try {
      if (_isSignUp) {
        UserCredential creds = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _pass.text.trim(),
        );
        await FirebaseFirestore.instance.collection('users').doc(creds.user!.uid).set({
          'email': _email.text.trim(),
          'role': _selectedRole,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _pass.text.trim(),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.tr(context, 'app_name'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 40),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _pass, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()), obscureText: true),
            if (_isSignUp) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(labelText: 'Select Role', border: OutlineInputBorder()),
                items: ['customer', 'seller', 'admin'].map((role) {
                  return DropdownMenuItem(value: role, child: Text(role.toUpperCase()));
                }).toList(),
                onChanged: (val) => setState(() => _selectedRole = val!),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(45)),
              onPressed: _submit,
              child: Text(_isSignUp ? 'Register' : 'Login'),
            ),
            TextButton(
              onPressed: () => setState(() => _isSignUp = !_isSignUp),
              child: Text(_isSignUp ? 'Have an account? Login' : 'New to Smart Bazaar? Register'),
            )
          ],
        ),
      ),
    );
  }
}

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final langProvider = Provider.of<AppLanguage>(context);
    final isEn = langProvider.appLocale.languageCode == 'en';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2874F0),
        title: Text(AppStrings.tr(context, 'app_name'), style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => langProvider.changeLanguage(Locale(isEn ? 'hi' : 'en')),
            child: Text(AppStrings.tr(context, 'switch_lang'), style: const TextStyle(color: Colors.yellowAccent)),
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart, color: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: AppStrings.tr(context, 'search_hint'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'Electronics', 'Fashion', 'Grocery'].map((cat) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: FilterChip(
                    label: Text(cat),
                    selected: _selectedCategory == cat,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('products').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final products = snapshot.data!.docs
                    .map((d) => Product.fromMap(d.id, d.data() as Map<String, dynamic>))
                    .where((p) {
                      final matchCat = _selectedCategory == 'All' || p.category == _selectedCategory;
                      final matchSearch = p.name.toLowerCase().contains(_searchQuery);
                      return matchCat && matchSearch;
                    }).toList();

                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: products.length,
                  itemBuilder: (ctx, i) {
                    final item = products[i];
                    return Card(
                      elevation: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: CachedNetworkImage(
                              imageUrl: item.imageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                              errorWidget: (_, __, ___) => const Icon(Icons.image),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('₹${item.price.toStringAsFixed(0)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF9f00),
                                    minimumSize: const Size.fromHeight(30),
                                  ),
                                  onPressed: () => Provider.of<CartProvider>(context, listen: false).addItem(item),
                                  child: Text(AppStrings.tr(context, 'add_to_cart'), style: const TextStyle(fontSize: 10, color: Colors.white)),
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    final items = cart.items.values.toList();

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.tr(context, 'cart'))),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                final item = items[i];
                return ListTile(
                  leading: Image.network(item.product.imageUrl, width: 50, height: 50, fit: BoxFit.cover),
                  title: Text(item.product.name),
                  subtitle: Text('Qty: ${item.quantity} x ₹${item.product.price}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => cart.removeItem(item.product.id),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total: ₹${cart.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ElevatedButton(
                  onPressed: cart.items.isEmpty ? null : () async {
                    final uid = FirebaseAuth.instance.currentUser!.uid;
                    await FirebaseFirestore.instance.collection('orders').add({
                      'customerId': uid,
                      'totalAmount': cart.totalAmount,
                      'items': cart.items.values.map((e) => {
                        'productId': e.product.id,
                        'name': e.product.name,
                        'price': e.product.price,
                        'quantity': e.quantity,
                        'sellerId': e.product.sellerId,
                      }).toList(),
                      'createdAt': FieldValue.serverTimestamp(),
                      'status': 'Pending',
                    });
                    cart.clearCart();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.tr(context, 'order_success'))));
                    Navigator.pop(context);
                  },
                  child: Text(AppStrings.tr(context, 'checkout')),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}

class SellerDashboard extends StatelessWidget {
  const SellerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.tr(context, 'seller_panel')),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddProductDialog(context, uid),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('products').where('sellerId', isEqualTo: uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              return ListTile(
                leading: Image.network(d['imageUrl'], width: 50, height: 50, fit: BoxFit.cover),
                title: Text(d['name']),
                subtitle: Text('Price: ₹${d['price']} | Category: ${d['category']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => FirebaseFirestore.instance.collection('products').doc(docs[i].id).delete(),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddProductDialog(BuildContext context, String sellerId) {
    final name = TextEditingController();
    final price = TextEditingController();
    final category = TextEditingController(text: 'Electronics');
    final desc = TextEditingController();
    final img = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.tr(context, 'add_product')),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: name, decoration: InputDecoration(labelText: AppStrings.tr(context, 'product_name'))),
              TextField(controller: price, decoration: InputDecoration(labelText: AppStrings.tr(context, 'price')), keyboardType: TextInputType.number),
              TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
              TextField(controller: img, decoration: InputDecoration(labelText: AppStrings.tr(context, 'image_url'))),
              TextField(controller: desc, decoration: InputDecoration(labelText: AppStrings.tr(context, 'description'))),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (name.text.isNotEmpty && price.text.isNotEmpty) {
                await FirebaseFirestore.instance.collection('products').add({
                  'sellerId': sellerId,
                  'name': name.text.trim(),
                  'price': double.parse(price.text.trim()),
                  'category': category.text.trim(),
                  'imageUrl': img.text.trim().isEmpty ? 'https://picsum.photos/200' : img.text.trim(),
                  'description': desc.text.trim(),
                  'createdAt': FieldValue.serverTimestamp(),
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          )
        ],
      ),
    );
  }
}

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppStrings.tr(context, 'admin_panel')),
          bottom: const TabBar(tabs: [Tab(text: "Products"), Tab(text: "Orders")]),
          actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())],
        ),
        body: TabBarView(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('products').snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                return ListView(
                  children: snap.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text(data['name']),
                      subtitle: Text("₹${data['price']} | Seller: ${data['sellerId']}"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => FirebaseFirestore.instance.collection('products').doc(doc.id).delete(),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('orders').snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                return ListView(
                  children: snap.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text("Order ID: ${doc.id}"),
                      subtitle: Text("Total: ₹${data['totalAmount']} | Status: ${data['status']}"),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
