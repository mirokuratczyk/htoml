{-# LANGUAGE OverloadedStrings #-}
module Text.TOML where

import qualified Data.Attoparsec.ByteString.Char8 as A
import qualified Data.ByteString.Char8 as B
import Data.List ( foldl', groupBy )
import Data.Either ( partitionEithers, either, rights )
import Data.Map ( Map )
import qualified Data.Map as M

import Text.TOML.Parser
import Text.TOML.Value


type KeyGroup = ([B.ByteString], [(B.ByteString, TOMLV)])

parse :: B.ByteString -> Maybe TOML
parse bs = process `fmap` parse' bs

parse' bs = (A.maybeResult $ A.feed (A.parse document bs) "")

process :: [Token] -> TOML
process ts = go (group ts) tempty
  where
    go []             m = m
    go ((ks, kvs):gs) m = go gs (okalter ks kvs m)

    okalter :: [B.ByteString] -> [(B.ByteString, TOMLV)] -> TOML -> TOML
    okalter []     kvs t = insertMany kvs t
    okalter (k:ks) kvs t = liftT (M.alter (Just . f) (B.unpack k)) t
      where f Nothing   = liftTV (okalter ks kvs) (Left tempty)
            f (Just t') = liftTV (okalter ks kvs) t'

    insertMany :: [(B.ByteString, TOMLV)] -> TOML -> TOML
    insertMany kvs m = foldl' (flip $ uncurry tinsert) m kvs'
      where kvs' = [(B.unpack k, Right v) | (k, v) <- kvs]

-- NB: groupBy will never produce an empty group.
group ts = alternate $ (map omg) $ (groupBy right ts)
  where 
    omg ls@((Left l):_)  = Left l
    omg rs@((Right _):_) = Right (rights rs)
    -- Only key-value pairs are grouped together
    right (Right _) (Right _) = True
    right _         _         = False

    -- If the token list starts with a Right, then there are key-value pairs that
    -- don't belong to a keygroup. Assign that one the 'empty' keygroup, and match
    -- pairs. If the token list starts with a right, then there are no "global"
    -- key-value pairs, and it's ok to straight zip the partition.
    --
    alternate                          []  = []
    alternate ((Left l)              : []) = (l , []) : []
    alternate ((Right r)             : gs) = ([], r ) : (alternate gs)
    alternate ((Left l ) : (Right r) : gs) = (l , r ) : (alternate gs)
    alternate ((Left l1) : (Left l2) : gs) = (l1, []) : (alternate $ (Left l2) : gs)

