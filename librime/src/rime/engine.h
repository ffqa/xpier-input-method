//
// Copyright RIME Developers
// Distributed under the BSD License
//
// 2011-03-14 GONG Chen <chen.sst@gmail.com>
//
#ifndef RIME_ENGINE_H_
#define RIME_ENGINE_H_

#include <rime_api.h>
#include <rime/common.h>
#include <rime/messenger.h>

namespace rime {

class KeyEvent;
class Schema;
class Context;

class Engine : public Messenger {
 public:
  using CommitSink = signal<void(const string& commit_text)>;

  virtual ~Engine();
  virtual bool ProcessKey(const KeyEvent& key_event) { return false; }
  virtual void ApplySchema(Schema* schema) {}
  virtual void CommitText(string text) { sink_(text); }
  virtual void Compose(Context* ctx) {}
  // FR-4b: 将最近一次上屏词立即置顶（由 ConcreteEngine 转发给翻译器）
  virtual bool PromoteLastCommit() { return false; }

  Schema* schema() const { return schema_.get(); }
  Context* context() const { return context_.get(); }
  CommitSink& sink() { return sink_; }

  Engine* active_engine() { return active_engine_ ? active_engine_ : this; }
  void set_active_engine(Engine* engine = nullptr) { active_engine_ = engine; }

  RIME_DLL static Engine* Create();

 protected:
  Engine();

  the<Schema> schema_;
  the<Context> context_;
  CommitSink sink_;
  Engine* active_engine_ = nullptr;
};

}  // namespace rime

#endif  // RIME_ENGINE_H_
