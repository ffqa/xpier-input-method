/*
 * rime_probe —— 在**不碰用户配置**的前提下驱动一次 Rime 引擎，打印候选。
 *
 * 为什么需要它：librime 自带的 rime_api_console 用的是默认目录，
 * 而且启动时会做一次 full_check 部署 —— 跑一次就会把 ~/Library/Xpier/build
 * 按它自己的 shared_data_dir 重新生成，等于动了用户的配置。（踩过一次。）
 * 本探针把 shared_data_dir / user_data_dir 全部显式指到调用方给的位置，
 * 用户目录只读不写。
 *
 * 用法: rime_probe <shared_data_dir> <user_data_dir> <schema_id> <键序列>...
 * 例:   rime_probe dist/Xpier.app/Contents/SharedSupport /tmp/probe wubi86_jidian tffu tzfu
 */
#include <stdio.h>
#include <string.h>
#include <rime_api.h>

static void on_message(void* context_object,
                       RimeSessionId session_id,
                       const char* message_type,
                       const char* message_value) {
  (void)context_object; (void)session_id; (void)message_type; (void)message_value;
}

static void dump(RimeSessionId session_id) {
  RimeApi* rime = rime_get_api();
  RIME_STRUCT(RimeCommit, commit);
  RIME_STRUCT(RimeContext, context);
  RIME_STRUCT(RimeStatus, status);

  if (rime->get_commit(session_id, &commit)) {
    printf("  上屏: %s\n", commit.text);
    rime->free_commit(&commit);
  }
  if (rime->get_status(session_id, &status)) {
    printf("  状态: composing=%d ascii=%d full=%d simplified=%d\n",
           status.is_composing, status.is_ascii_mode,
           status.is_full_shape, status.is_simplified);
    rime->free_status(&status);
  }
  if (rime->get_context(session_id, &context)) {
    printf("  输入串: %s\n", context.composition.preedit ? context.composition.preedit : "(空)");
    printf("  候选 %d 个:\n", context.menu.num_candidates);
    for (int i = 0; i < context.menu.num_candidates && i < 12; ++i) {
      printf("     %2d. %-6s %s\n", i + 1,
             context.menu.candidates[i].text,
             context.menu.candidates[i].comment ? context.menu.candidates[i].comment : "");
    }
    rime->free_context(&context);
  }
}

int main(int argc, char** argv) {
  if (argc < 5) {
    fprintf(stderr, "用法: %s <shared_data_dir> <user_data_dir> <schema_id> <键序列>...\n", argv[0]);
    return 1;
  }
  RimeApi* rime = rime_get_api();
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = argv[1];
  traits.user_data_dir = argv[2];
  traits.app_name = "rime.probe";
  rime->setup(&traits);
  rime->set_notification_handler(on_message, NULL);
  rime->initialize(NULL);
  if (rime->start_maintenance(True)) {
    rime->join_maintenance_thread();
  }

  RimeSessionId session_id = rime->create_session();
  if (!session_id) {
    fprintf(stderr, "创建会话失败\n");
    return 1;
  }
  if (!rime->select_schema(session_id, argv[3])) {
    fprintf(stderr, "选择方案失败: %s\n", argv[3]);
    return 1;
  }
  char current[128] = {0};
  rime->get_current_schema(session_id, current, sizeof(current));
  printf("方案: %s\n\n", current);

  for (int i = 4; i < argc; ++i) {
    // 以 + 开头的参数不是按键，而是「打开一个 Rime 开关」，用来验证
    // 菜单开关背后的引擎链路（如 +zh_trad 验证输简出繁）。
    // 开关一旦打开，对本会话后续所有的键序列都生效。
    if (argv[i][0] == '+' && argv[i][1] != '\0') {
      const char* option = argv[i] + 1;
      rime->set_option(session_id, option, True);
      printf("=== 开关 +%s（当前=%d）===\n\n",
             option, (int)rime->get_option(session_id, option));
      continue;
    }
    printf("=== 输入 \"%s\" ===\n", argv[i]);
    if (!rime->simulate_key_sequence(session_id, argv[i])) {
      printf("  （键序列无法解析）\n");
    } else {
      dump(session_id);
    }
    rime->simulate_key_sequence(session_id, "{Escape}");
    printf("\n");
  }

  rime->destroy_session(session_id);
  rime->finalize();
  return 0;
}
