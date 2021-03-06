/* $Header: /var/lib/cvs/dynare_cpp/sylv/cc/QuasiTriangularZero.h,v 1.1.1.1 2004/06/04 13:00:44 kamenik Exp $ */

/* Tag $Name:  $ */

#ifndef QUASI_TRIANGULAR_ZERO_H
#define QUASI_TRIANGULAR_ZERO_H

#include "QuasiTriangular.hh"
#include "GeneralMatrix.hh"

#include <memory>

class QuasiTriangularZero : public QuasiTriangular
{
  int nz; // number of zero columns
  GeneralMatrix ru; // data in right upper part (nz,d_size)
public:
  QuasiTriangularZero(int num_zeros, const ConstVector &d, int d_size);
  QuasiTriangularZero(double r, const QuasiTriangularZero &t);
  QuasiTriangularZero(double r, const QuasiTriangularZero &t,
                      double rr, const QuasiTriangularZero &tt);
  QuasiTriangularZero(int p, const QuasiTriangularZero &t);
  QuasiTriangularZero(const QuasiTriangular &t);
  QuasiTriangularZero(const SchurDecompZero &decomp);
  ~QuasiTriangularZero() override = default;
  void solvePre(Vector &x, double &eig_min) override;
  void solvePreTrans(Vector &x, double &eig_min) override;
  void multVec(Vector &x, const ConstVector &b) const override;
  void multVecTrans(Vector &x, const ConstVector &b) const override;
  void multaVec(Vector &x, const ConstVector &b) const override;
  void multaVecTrans(Vector &x, const ConstVector &b) const override;
  void multKron(KronVector &x) const override;
  void multKronTrans(KronVector &x) const override;
  void multLeftOther(GeneralMatrix &a) const override;
  /* clone */
  std::unique_ptr<QuasiTriangular>
  clone() const override
  {
    return std::make_unique<QuasiTriangularZero>(*this);
  }
  std::unique_ptr<QuasiTriangular>
  clone(int p, const QuasiTriangular &t) const override
  {
    return std::make_unique<QuasiTriangularZero>(p, (const QuasiTriangularZero &) t);
  }
  std::unique_ptr<QuasiTriangular>
  clone(double r) const override
  {
    return std::make_unique<QuasiTriangularZero>(r, *this);
  }
  std::unique_ptr<QuasiTriangular>
  clone(double r, double rr, const QuasiTriangular &tt) const override
  {
    return std::make_unique<QuasiTriangularZero>(r, *this, rr, (const QuasiTriangularZero &) tt);
  }
  void print() const override;
};

#endif /* QUASI_TRIANGULAR_ZERO_H */
