import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

class DireitoAcessoPage extends StatefulWidget {
  final String? adminId;
  final String? adminNome;

  const DireitoAcessoPage({super.key, this.adminId, this.adminNome});

  // Método estático blindado: padrão é liberar tudo para evitar bloqueios indesejados
  static Future<Map<String, bool>> carregarPermissoesAdmin() async {
    Map<String, bool> permissoesMaster = {
      'dashboard': true,
      'config_planos': true,
      'premiacao': true,
      'selo_verificacao': true,
      'usuarios': true,
      'administradores': true,
      'notificacoes_push': true,
    };

    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      final user = session?.user ?? client.auth.currentUser;

      // Se não houver usuário logado, retorna falso
      if (user == null) {
        return {
          'dashboard': false,
          'config_planos': false,
          'premiacao': false,
          'selo_verificacao': false,
          'usuarios': false,
          'administradores': false,
          'notificacoes_push': false,
        };
      }

      final emailUser = user.email?.toLowerCase().trim() ?? '';

      // SE FOR VOCÊ (Master absoluto por e-mail), libera tudo imediatamente
      if (emailUser == 'juniorjaskiw@hotmail.com') {
        return permissoesMaster;
      }

      // Busca o registro na tabela de admins
      var adminRecord = await client
          .from('tab_admin_users')
          .select('id, email, cargo')
          .ilike('email', emailUser)
          .maybeSingle();

      // SEGURANÇA MESTRE: Se o admin não estiver cadastrado na tabela ainda,
      // liberamos acesso total temporariamente para você não ficar preso (Fail-Open).
      if (adminRecord == null) {
        return permissoesMaster;
      }

      final cargo = adminRecord['cargo']?.toString().toLowerCase().trim() ?? '';
      if (cargo == 'master' || cargo == 'gerente' || cargo.isEmpty) {
        return permissoesMaster;
      }

      String adminIdRef = adminRecord['id'].toString();

      // Busca restrições específicas na tabela tab_direito_acessos
      final response = await client
          .from('tab_direito_acessos')
          .select('permissoes')
          .eq('admin_id', adminIdRef)
          .maybeSingle();

      if (response == null || response['permissoes'] == null) {
        return permissoesMaster;
      }

      Map<String, bool> permissoesAbas = Map.from(permissoesMaster);
      final permissoesRaw = response['permissoes'];
      Map<String, dynamic> data = {};

      if (permissoesRaw is Map) {
        data = Map<String, dynamic>.from(permissoesRaw);
      } else if (permissoesRaw is String && permissoesRaw.isNotEmpty) {
        try {
          data = Map<String, dynamic>.from(jsonDecode(permissoesRaw));
        } catch (_) {}
      }

      final abasBanco = data['abas'];
      if (abasBanco is Map) {
        abasBanco.forEach((key, val) {
          if (permissoesAbas.containsKey(key)) {
            permissoesAbas[key] = val == true;
          }
        });
      }

      return permissoesAbas;
    } catch (e) {
      debugPrint('Erro ao carregar permissões: $e');
      // Em caso de qualquer erro de conexão ou banco, libera tudo para não trancar o painel
      return permissoesMaster;
    }
  }

  @override
  State<DireitoAcessoPage> createState() => _DireitoAcessoPageState();
}

class _DireitoAcessoPageState extends State<DireitoAcessoPage> {
  bool _carregando = true;
  bool _salvando = false;
  bool _salvandoCargo = false;
  List<Map<String, dynamic>> _listaAdmins = [];
  String? _adminSelecionadoId;
  String _nomeUsuarioLogado = 'Administrador';
  String _cargoSelecionadoAtual = 'atendente';

  Map<String, bool> _permissoesAbas = {
    'dashboard': true,
    'config_planos': true,
    'premiacao': true,
    'selo_verificacao': true,
    'usuarios': true,
    'administradores': true,
    'notificacoes_push': true,
  };

  final Map<String, String> _nomesAbasLegiveis = {
    'dashboard': 'Dashboard',
    'config_planos': 'Configuração dos Planos',
    'premiacao': 'Premiação',
    'selo_verificacao': 'Selo de Verificação',
    'usuarios': 'Usuários',
    'administradores': 'Administradores',
    'notificacoes_push': 'Notificações Push',
  };

  @override
  void initState() {
    super.initState();
    _identificarUsuarioLogadoEAdmins();
  }

  Future<void> _identificarUsuarioLogadoEAdmins() async {
    setState(() => _carregando = true);
    try {
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      final user = session?.user ?? client.auth.currentUser;

      if (user != null) {
        final emailUser = user.email?.toLowerCase().trim() ?? '';
        try {
          var adminRec = await client
              .from('tab_admin_users')
              .select('nome, email, cargo')
              .ilike('email', emailUser)
              .maybeSingle();

          if (adminRec != null && adminRec['nome'] != null) {
            _nomeUsuarioLogado = adminRec['nome'].toString();
          } else {
            _nomeUsuarioLogado =
                widget.adminNome ?? user.email ?? 'Administrador';
          }
        } catch (err) {
          debugPrint('Erro ao buscar dados do admin logado: $err');
          _nomeUsuarioLogado =
              widget.adminNome ?? user.email ?? 'Administrador';
        }
      } else {
        _nomeUsuarioLogado = widget.adminNome ?? 'Administrador';
      }

      await _carregarAdmins();
    } catch (e) {
      debugPrint('Erro ao identificar usuário logado: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _carregarAdmins() async {
    try {
      final response =
          await Supabase.instance.client.from('tab_admin_users').select('*');

      if (mounted) {
        setState(() {
          _listaAdmins = List<Map<String, dynamic>>.from(response);
          if (_listaAdmins.isNotEmpty) {
            if (widget.adminId != null) {
              _adminSelecionadoId = widget.adminId;
            } else {
              _adminSelecionadoId = _listaAdmins.first['id']?.toString();
            }
            _atualizarCargoSelecionadoLocal();
          }
        });
        if (_adminSelecionadoId != null) {
          await _carregarPermissoesDoAdmin(_adminSelecionadoId!);
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar administradores: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _atualizarCargoSelecionadoLocal() {
    if (_adminSelecionadoId == null) return;
    final adminObj = _listaAdmins.firstWhere(
      (a) => a['id']?.toString() == _adminSelecionadoId,
      orElse: () => {},
    );
    if (adminObj.isNotEmpty) {
      final c = adminObj['cargo']?.toString().toLowerCase().trim();
      if (c == 'master' || c == 'gerente' || c == 'atendente') {
        _cargoSelecionadoAtual = c!;
      } else {
        _cargoSelecionadoAtual = 'atendente';
      }
    }
  }

  Future<void> _alterarCargoAdmin() async {
    if (_adminSelecionadoId == null) return;

    setState(() => _salvandoCargo = true);

    try {
      await Supabase.instance.client.from('tab_admin_users').update(
          {'cargo': _cargoSelecionadoAtual}).eq('id', _adminSelecionadoId!);

      setState(() {
        for (var adm in _listaAdmins) {
          if (adm['id']?.toString() == _adminSelecionadoId) {
            adm['cargo'] = _cargoSelecionadoAtual;
          }
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Cargo alterado para "${_cargoSelecionadoAtual.toUpperCase()}" com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao alterar cargo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _salvandoCargo = false);
    }
  }

  Future<void> _carregarPermissoesDoAdmin(String adminId) async {
    setState(() => _carregando = true);
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('tab_direito_acessos')
          .select('permissoes')
          .eq('admin_id', adminId)
          .maybeSingle();

      Map<String, bool> permissoesAtuais = {
        'dashboard': true,
        'config_planos': true,
        'premiacao': true,
        'selo_verificacao': true,
        'usuarios': true,
        'administradores': true,
        'notificacoes_push': true,
      };

      if (response != null && response['permissoes'] != null) {
        final permissoesRaw = response['permissoes'];
        Map<String, dynamic> data = {};

        if (permissoesRaw is Map) {
          data = Map<String, dynamic>.from(permissoesRaw);
        } else if (permissoesRaw is String && permissoesRaw.isNotEmpty) {
          try {
            data = Map<String, dynamic>.from(jsonDecode(permissoesRaw));
          } catch (_) {}
        }

        final abasBanco = data['abas'];
        if (abasBanco is Map) {
          abasBanco.forEach((key, val) {
            if (permissoesAtuais.containsKey(key)) {
              permissoesAtuais[key] = val == true;
            }
          });
        }
      }

      if (mounted) {
        setState(() {
          _permissoesAbas = permissoesAtuais;
          _carregando = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar permissões do admin: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvarPermissoes() async {
    if (_adminSelecionadoId == null) return;
    setState(() => _salvando = true);

    try {
      final client = Supabase.instance.client;
      final jsonPermissoes = {
        'abas': _permissoesAbas,
      };

      await client.from('tab_direito_acessos').upsert({
        'admin_id': _adminSelecionadoId,
        'permissoes': jsonPermissoes,
      }, onConflict: 'admin_id');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permissões salvas com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar permissões: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101B2B),
        title: const Text('Gerenciar Direitos de Acesso',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101B2B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFFF8C00).withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_circle,
                            color: Color(0xFFFF8C00), size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Usuário Logado:',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _nomeUsuarioLogado,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.greenAccent),
                          ),
                          child: const Text(
                            'MASTER ADMIN',
                            style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Selecione o Administrador:',
                    style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _adminSelecionadoId,
                    dropdownColor: const Color(0xFF101B2B),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Color(0xFF101B2B),
                      border: OutlineInputBorder(),
                    ),
                    items: _listaAdmins.map((admin) {
                      final id = admin['id']?.toString() ?? '';
                      final nome = admin['nome'] ?? admin['email'] ?? 'Admin';
                      final cargoAdmin = admin['cargo'] ?? 'atendente';
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text(
                            '$nome (${cargoAdmin.toString().toUpperCase()})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _adminSelecionadoId = val;
                        });
                        _atualizarCargoSelecionadoLocal();
                        _carregarPermissoesDoAdmin(val);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Definir Cargo do Administrador Selecionado:',
                    style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: ['master', 'gerente', 'atendente']
                                  .contains(_cargoSelecionadoAtual)
                              ? _cargoSelecionadoAtual
                              : 'atendente',
                          dropdownColor: const Color(0xFF101B2B),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            filled: true,
                            fillColor: Color(0xFF101B2B),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'master', child: Text('Master')),
                            DropdownMenuItem(
                                value: 'gerente', child: Text('Gerente')),
                            DropdownMenuItem(
                                value: 'atendente', child: Text('Atendente')),
                          ],
                          onChanged: (novoCargo) {
                            if (novoCargo != null) {
                              setState(() {
                                _cargoSelecionadoAtual = novoCargo;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8C00),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 18),
                        ),
                        onPressed: _salvandoCargo ? null : _alterarCargoAdmin,
                        child: _salvandoCargo
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'SALVAR CARGO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Permissões de Abas no Painel:',
                    style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Ative ou desative quais abas este administrador pode visualizar e gerenciar.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF101B2B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _permissoesAbas.keys.length,
                      separatorBuilder: (context, index) =>
                          const Divider(color: Colors.white12, height: 1),
                      itemBuilder: (context, index) {
                        final key = _permissoesAbas.keys.elementAt(index);
                        final nomeLegivel = _nomesAbasLegiveis[key] ?? key;
                        final permitido = _permissoesAbas[key] ?? false;

                        return SwitchListTile(
                          title: Text(
                            nomeLegivel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            permitido ? 'Acesso Permitido' : 'Acesso Restrito',
                            style: TextStyle(
                              color: permitido
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                          value: permitido,
                          activeColor: const Color(0xFFFF8C00),
                          onChanged: (bool value) {
                            setState(() {
                              _permissoesAbas[key] = value;
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C00),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _salvando ? null : _salvarPermissoes,
                      child: _salvando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'SALVAR PERMISSÕES',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
