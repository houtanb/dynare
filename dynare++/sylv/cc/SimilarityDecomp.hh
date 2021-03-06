/* $Header: /var/lib/cvs/dynare_cpp/sylv/cc/SimilarityDecomp.h,v 1.1.1.1 2004/06/04 13:00:44 kamenik Exp $ */

/* Tag $Name:  $ */

#ifndef SIMILARITY_DECOMP_H
#define SIMILARITY_DECOMP_H

#include "SylvMatrix.hh"
#include "BlockDiagonal.hh"
#include "SylvParams.hh"

#include <memory>

class SimilarityDecomp
{
  std::unique_ptr<SqSylvMatrix> q;
  std::unique_ptr<BlockDiagonal> b;
  std::unique_ptr<SqSylvMatrix> invq;
  using diag_iter = BlockDiagonal::diag_iter;
public:
  SimilarityDecomp(const ConstVector &d, int d_size, double log10norm = 3.0);
  virtual ~SimilarityDecomp() = default;
  const SqSylvMatrix &
  getQ() const
  {
    return *q;
  }
  const SqSylvMatrix &
  getInvQ() const
  {
    return *invq;
  }
  const BlockDiagonal &
  getB() const
  {
    return *b;
  }
  void check(SylvParams &pars, const GeneralMatrix &m) const;
  void infoToPars(SylvParams &pars) const;
protected:
  void getXDim(diag_iter start, diag_iter end, int &rows, int &cols) const;
  bool solveX(diag_iter start, diag_iter end, GeneralMatrix &X, double norm) const;
  void updateTransform(diag_iter start, diag_iter end, GeneralMatrix &X);
  void bringGuiltyBlock(diag_iter start, diag_iter &end);
  void diagonalize(double norm);
};

#endif /* SIMILARITY_DECOMP_H */
