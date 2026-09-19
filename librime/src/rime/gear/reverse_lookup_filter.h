//
// Copyright RIME Developers
// Distributed under the BSD License
//
// 2013-11-05 GONG Chen <chen.sst@gmail.com>
//
#ifndef RIME_REVERSE_LOOKUP_FILTER_H_
#define RIME_REVERSE_LOOKUP_FILTER_H_

#include <rime/common.h>
#include <rime/filter.h>
#include <rime/algo/algebra.h>
#include <rime/gear/filter_commons.h>

namespace rime {

class ReverseLookupDictionary;

class ReverseLookupFilter : public Filter, TagMatching {
 public:
  explicit ReverseLookupFilter(const Ticket& ticket);

  virtual an<Translation> Apply(an<Translation> translation,
                                CandidateList* candidates);

  virtual bool AppliesToSegment(Segment* segment);

  void Process(const an<Candidate>& cand);

 protected:
  void Initialize();

  bool initialized_ = false;
  the<ReverseLookupDictionary> rev_dict_;
  // settings
  bool overwrite_comment_ = false;
  bool append_comment_ = false;
  Projection comment_formatter_;
  // 可选：只在当前段输入包含该子串时才注音。
  // 例：wubi_code/show_if_input_contains: "z" —— 首位 z（拼音反查）和
  // 中间位 z（万能键）都显示编码；平时不含 z 的输入完全不显示。
  // 为空表示不限制（老行为）。
  string show_if_input_contains_;
};

}  // namespace rime

#endif  // RIME_REVERSE_LOOKUP_FILTER_H_
