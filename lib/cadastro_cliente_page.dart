import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/feed_page.dart';

class CadastroClientePage extends StatefulWidget {
  const CadastroClientePage({super.key});

  @override
  State<CadastroClientePage> createState() => _CadastroClientePageState();
}

class _CadastroClientePageState extends State<CadastroClientePage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  File? _arquivoImagemSelecionado; // Para mobile (Android/iOS)
  Uint8List? _bytesImagemSelecionada; // Para Web

  final List<String> _listaEstados = [
    "AC",
    "AL",
    "AM",
    "AP",
    "BA",
    "CE",
    "DF",
    "ES",
    "GO",
    "MA",
    "MG",
    "MS",
    "MT",
    "PA",
    "PB",
    "PE",
    "PI",
    "PR",
    "RJ",
    "RN",
    "RO",
    "RR",
    "RS",
    "SC",
    "SE",
    "SP",
    "TO"
  ];

  String? _estadoSelecionado;
  String? _cidadeSelecionada;
  List<String> _listaCidades = [];
  bool _carregandoCidades = false;
  bool _isLoading = false;
  bool _aceitouTermos = false;
  bool _permanecerConectado = true;

  final Color _bgColor = const Color(0xFF1A2C42);
  final Color _primaryColor = const Color(0xFFFF8C00);

  Future<void> _buscarCidades(String estado) async {
    setState(() {
      _carregandoCidades = true;
      _listaCidades = [];
      _cidadeSelecionada = null;
    });

    try {
      final data = await Supabase.instance.client
          .from('tab_localidades')
          .select('municipio')
          .eq('estado', estado)
          .order('municipio', ascending: true);

      setState(() {
        _listaCidades =
            (data as List).map((e) => e['municipio'] as String).toList();
        _carregandoCidades = false;
      });
    } catch (e) {
      setState(() => _carregandoCidades = false);
      debugPrint('Erro ao buscar cidades: $e');
    }
  }

  Future<void> _selecionarImagem() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _bytesImagemSelecionada = bytes;
        });
      } else {
        setState(() {
          _arquivoImagemSelecionado = File(pickedFile.path);
        });
      }
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _realizarCadastro() async {
    if (!_aceitouTermos ||
        _estadoSelecionado == null ||
        _cidadeSelecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Preencha todos os campos e aceite os termos!'),
          backgroundColor: Colors.orange));
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      // 1. Criação do usuário no Auth
      final AuthResponse response = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _senhaController.text.trim(),
        data: {'nome': _nomeController.text.trim()},
      );

      if (response.user != null) {
        final userId = response.user!.id;
        String? fotoUrl;

        // 2. Upload da foto se houver uma selecionada
        if (_arquivoImagemSelecionado != null ||
            _bytesImagemSelecionada != null) {
          final fileName =
              'perfil_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final path = 'public/$fileName';

          if (kIsWeb) {
            await supabase.storage.from('fotos_perfil').uploadBinary(
                  path,
                  _bytesImagemSelecionada!,
                  fileOptions: const FileOptions(upsert: true),
                );
          } else {
            await supabase.storage.from('fotos_perfil').upload(
                  path,
                  _arquivoImagemSelecionado!,
                  fileOptions: const FileOptions(upsert: true),
                );
          }

          fotoUrl = supabase.storage.from('fotos_perfil').getPublicUrl(path);
        }

        // 3. Inserção na tabela tab_usuarios com a foto_url
        await supabase.from('tab_usuarios').insert({
          'id': userId,
          'usuario_nome': _nomeController.text.trim(),
          'whatsapp': _whatsappController.text.trim(),
          'email': _emailController.text.trim(),
          'estado': _estadoSelecionado,
          'cidade': _cidadeSelecionada,
          'foto_url': fotoUrl,
          'usuario_status': 'aguardando',
          'usuario_tipo': 'cliente',
          'dt_cadastro': DateTime.now().toIso8601String(),
        });

        if (mounted) {
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (context) => const FeedPage()));
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: $error'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: _primaryColor)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // QUADRO / AVATAR PARA INSERIR A FOTO
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.white24,
                        backgroundImage: _bytesImagemSelecionada != null
                            ? MemoryImage(_bytesImagemSelecionada!)
                            : (_arquivoImagemSelecionado != null
                                ? FileImage(_arquivoImagemSelecionado!)
                                    as ImageProvider
                                : null),
                        child: (_arquivoImagemSelecionado == null &&
                                _bytesImagemSelecionada == null)
                            ? Icon(Icons.person, size: 50, color: _primaryColor)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: InkWell(
                          onTap: _selecionarImagem,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Toque na câmera para adicionar foto",
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 20),

                _buildTextFormField(
                    controller: _nomeController,
                    label: 'NOME COMPLETO',
                    icon: Icons.person_outline),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                      labelText: 'ESTADO',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.map, color: Color(0xFFFF8C00))),
                  items: _listaEstados
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (value) {
                    setState(() => _estadoSelecionado = value);
                    _buscarCidades(value!);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                      labelText: 'CIDADE',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon:
                          Icon(Icons.location_city, color: Color(0xFFFF8C00))),
                  value: _cidadeSelecionada,
                  items: _listaCidades
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: _carregandoCidades
                      ? null
                      : (value) => setState(() => _cidadeSelecionada = value),
                ),
                const SizedBox(height: 16),
                _buildTextFormField(
                    controller: _whatsappController,
                    label: 'WHATSAPP',
                    icon: Icons.phone_android,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 16),
                _buildTextFormField(
                    controller: _emailController,
                    label: 'E-MAIL',
                    icon: Icons.email_outlined),
                const SizedBox(height: 16),
                _buildTextFormField(
                    controller: _senhaController,
                    label: 'SENHA',
                    icon: Icons.lock_outline,
                    obscureText: true),
                const SizedBox(height: 20),
                CheckboxListTile(
                    title: const Text('Permanecer conectado',
                        style: TextStyle(color: Colors.white)),
                    value: _permanecerConectado,
                    onChanged: (val) =>
                        setState(() => _permanecerConectado = val!),
                    activeColor: _primaryColor),
                CheckboxListTile(
                    title: const Text('Li e aceito os termos',
                        style: TextStyle(color: Colors.white)),
                    value: _aceitouTermos,
                    onChanged: (val) => setState(() => _aceitouTermos = val!),
                    activeColor: _primaryColor),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                      onPressed: _isLoading ? null : _realizarCadastro,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('CRIAR CONTA',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextFormField(
      {required TextEditingController controller,
      required String label,
      required IconData icon,
      bool obscureText = false,
      TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.black),
      decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon, color: _primaryColor),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
    );
  }
}
