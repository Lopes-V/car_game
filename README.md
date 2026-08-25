# Corrida Construção — MVP v0.1

Protótipo local para duas pessoas feito em Godot 4. A pista linear cresce a cada rodada: um jogador escolhe uma extensão e o outro instala gelo ou dinamite em um slot existente. Os papéis alternam, as armadilhas permanecem e a partida termina em 20 pontos ou após cinco rodadas.

## Como jogar

1. Abra `project.godot` no Godot 4 ou execute o projeto pela linha de comando.
2. Na tela de construção, o jogador indicado escolhe uma extensão e trava a escolha.
3. Passe o controle ao outro jogador. Ele escolhe a armadilha e três slots diferentes em ordem de preferência, então trava a escolha.
4. As duas escolhas permanecem visíveis na fase de revelação. Confirme em **APLICAR E CORRER**; somente então a pista é alterada e começa a contagem de três segundos.
5. Na tela de resultados, use **PRÓXIMA RODADA** para continuar. Uma partida encerrada não reinicia automaticamente a pista acumulada.

### Controles

| Ação | Jogador 1 | Jogador 2 |
| --- | --- | --- |
| Acelerar | `W` | `↑` |
| Frear / ré | `S` | `↓` |
| Virar | `A` / `D` | `←` / `→` |
| Boost | `Shift esquerdo` | `Enter` |

Cada jogador recebe três vidas e uma carga de boost no início de cada rodada. A carga é consumida inteira e não recarrega durante a corrida.

## Regras principais

- A corrida dura no máximo 120 segundos.
- O primeiro carro a terminar abre uma janela final de 15 segundos.
- Gelo reduz temporariamente a aderência; dinamite remove uma vida e dispara uma vez por corrida.
- Se a extensão for aplicada mas os três slots de armadilha ficarem indisponíveis, a extensão permanece, o HUD informa a falha da modificação e a corrida continua. Uma extensão invalidada encerra a partida de forma controlada.
- Um carro morto reaparece no próprio último ponto seguro quando o adversário ativa um ponto de respawn.
- Se todos estiverem mortos, quem ainda tiver vidas reaparece automaticamente.
- A classificação usa chegada e, para quem não chegou, o progresso em metros ao longo da cadeia lógica da pista.

## Executar e verificar

No PowerShell, a partir da raiz do repositório:

```powershell
$godot = & .\tools\find_godot.ps1
& $godot --path .
```

Suite automatizada, importação do editor e higiene do diff:

```powershell
$godot = & .\tools\find_godot.ps1
& $godot --headless --path . -s res://tests/test_runner.gd
& $godot --headless --path . --editor --quit
git diff --check
```

O MVP não inclui online, bots, bifurcações, rampas, loops, customização, inventário ou power-ups adicionais.
